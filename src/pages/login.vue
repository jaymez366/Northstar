<script setup lang="ts">
  import { computed, nextTick, onMounted, ref } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const route = useRoute()
  const router = useRouter()
  const isSignup = ref(false)
  const fullName = ref('')
  const email = ref('')
  const password = ref('')
  const passwordVisible = ref(false)
  const passwordInput = ref<HTMLInputElement | null>(null)
  const confirmPassword = ref('')
  const errorMessage = ref('')
  const noticeMessage = ref('')
  const signupConfirmationEmail = ref('')
  const busy = ref(false)
  const resetBusy = ref(false)
  const showPasswordResetForm = ref(false)
  const resetEmail = ref('')
  const submitButtonLabel = computed(() => {
    return isSignup.value ? 'Create account' : 'Sign in'
  })

  onMounted(() => {
    if (route.query.reset === 'success') {
      noticeMessage.value = 'Your password has been reset. Sign in with your new password.'
    }
  })

  async function submitForm () {
    if (busy.value) return

    busy.value = true
    errorMessage.value = ''
    noticeMessage.value = ''

    try {
      if (isSignup.value) {
        if (password.value.length < 8) {
          errorMessage.value = 'Your password must be at least 8 characters.'
          return
        }

        if (password.value !== confirmPassword.value) {
          errorMessage.value = 'Your passwords do not match.'
          return
        }

        if (!fullName.value.trim()) {
          errorMessage.value = 'Enter your name to create an account.'
          return
        }

        const result = await auth.signup(email.value.trim(), password.value, fullName.value)
        if (!result.success) {
          errorMessage.value = auth.errorMessage || 'Your account could not be created.'
          return
        }
        if (result.requiresEmailConfirmation) {
          signupConfirmationEmail.value = email.value.trim()
          noticeMessage.value = `A verification email was requested for ${signupConfirmationEmail.value}. Click the link in that email to verify your account before signing in.`
          isSignup.value = false
          password.value = ''
          confirmPassword.value = ''
          return
        }
      } else {
        const success = await auth.login(email.value.trim(), password.value)
        if (!success) {
          errorMessage.value = auth.errorMessage || 'Sign in could not be completed.'
          return
        }
      }

      let redirect = '/employee-registration'
      if (auth.isAdmin) {
        redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/admin'
      } else if (auth.employeeRegistrationComplete) {
        if (!auth.canAccessEmployeeWorkspace) {
          redirect = '/pending-approval'
        } else if (typeof route.query.redirect === 'string') {
          redirect = route.query.redirect
        } else {
          redirect = '/overview'
        }
      }

      await router.push(redirect)
    } catch (error) {
      errorMessage.value = 'Northstar could not complete that request. Please try again.'
      console.error('Employee authentication form failed', error)
    } finally {
      busy.value = false
    }
  }

  async function sendPasswordReset () {
    if (resetBusy.value) return
    errorMessage.value = ''
    noticeMessage.value = ''
    if (!resetEmail.value.trim()) {
      errorMessage.value = 'Enter the email address for your Northstar account.'
      return
    }

    resetBusy.value = true
    try {
      if (await auth.resetPassword(resetEmail.value.trim())) {
        noticeMessage.value = 'If an account exists for that address, a password reset link has been sent.'
      } else {
        errorMessage.value = auth.errorMessage
      }
    } finally {
      resetBusy.value = false
    }
  }

  async function retryProfileLoad () {
    await auth.refreshProfile()
    if (!auth.profileLoaded) {
      errorMessage.value = auth.errorMessage || 'Your employee profile is temporarily unavailable. Please try again.'
      return
    }
    errorMessage.value = ''
    let destination = '/employee-registration'
    if (auth.isAdmin) {
      destination = '/admin'
    } else if (auth.employeeRegistrationComplete) {
      destination = auth.canAccessEmployeeWorkspace ? '/overview' : '/pending-approval'
    }
    await router.replace(destination)
  }

  function openPasswordReset () {
    resetEmail.value = email.value.trim()
    showPasswordResetForm.value = !showPasswordResetForm.value
    errorMessage.value = ''
    noticeMessage.value = ''
  }

  async function togglePasswordVisibility () {
    passwordVisible.value = !passwordVisible.value
    await nextTick()
    passwordInput.value?.focus()
  }

  function toggleMode () {
    isSignup.value = !isSignup.value
    errorMessage.value = ''
    noticeMessage.value = ''
    signupConfirmationEmail.value = ''
  }
</script>

<template>
  <main class="login-page">
    <nav aria-label="Main navigation" class="login-nav container">
      <router-link aria-label="Northstar home" class="brand" to="/">
        <span class="brand-mark"><span /><span /><span /></span>
        <span>northstar<span class="brand-dot">.</span></span>
      </router-link>

      <span class="nav-note">SECURE WORKSPACE ACCESS</span>
    </nav>

    <div class="login-layout container">
      <section class="login-intro">
        <p class="section-overline">WELCOME BACK</p>
        <h1>Keep your team<br><em>moving clearly.</em></h1>

        <p class="intro-copy">
          Sign in to access Northstar's communication and response workspace.
        </p>

        <div class="signal-list">
          <span><v-icon icon="mdi-check" size="15" /> One source of truth</span>
          <span><v-icon icon="mdi-check" size="15" /> Calm, coordinated action</span>
          <span><v-icon icon="mdi-check" size="15" /> Built for the moments that matter</span>
        </div>
      </section>

      <section aria-labelledby="login-title" class="login-panel">
        <div class="panel-heading">
          <p class="section-overline">NORTHSTAR ACCOUNT</p>
          <h2 id="login-title">{{ isSignup ? 'Create account' : 'Sign in' }}</h2>
        </div>

        <form @submit.prevent="submitForm">
          <template v-if="isSignup">
            <label for="full-name">Full name</label>

            <input
              id="full-name"
              v-model="fullName"
              autocomplete="name"
              placeholder="Alex Morgan"
              required
              type="text"
            >
          </template>

          <label for="email">Work email</label>

          <input
            id="email"
            v-model="email"
            autocomplete="email"
            placeholder="you@company.com"
            required
            type="email"
          >

          <label for="password">Password</label>

          <div class="password-field">
            <input
              id="password"
              ref="passwordInput"
              v-model="password"
              :autocomplete="isSignup ? 'new-password' : 'current-password'"
              placeholder="Enter your password"
              required
              :type="passwordVisible ? 'text' : 'password'"
            >
            <button
              :aria-label="passwordVisible ? 'Hide password' : 'Show password'"
              :aria-pressed="passwordVisible"
              class="password-visibility-toggle"
              type="button"
              @mousedown.prevent
              @click="togglePasswordVisibility"
            >
              <v-icon :icon="passwordVisible ? 'mdi-eye-off' : 'mdi-eye'" size="21" />
            </button>
          </div>

          <template v-if="isSignup">
            <label for="confirm-password">Confirm password</label>

            <input
              id="confirm-password"
              v-model="confirmPassword"
              autocomplete="new-password"
              placeholder="Repeat your password"
              required
              type="password"
            >
          </template>

          <p v-if="errorMessage || auth.errorMessage" class="error-message" role="alert">
            <v-icon icon="mdi-alert-circle-outline" size="16" /> {{ errorMessage || auth.errorMessage }}
          </p>

          <div v-if="auth.isAuthenticated && !auth.profileLoaded && auth.errorMessage" class="profile-retry">
            <span>Sign-in worked, but we could not retrieve your employee profile.</span>
            <button type="button" @click="retryProfileLoad">Retry profile lookup</button>
          </div>

          <router-link
            v-if="!isSignup"
            class="verification-link"
            :to="{ path: '/verify-email', query: { email: signupConfirmationEmail || email.trim() } }"
          >Resend confirmation email</router-link>

          <p v-if="noticeMessage" class="success-message" role="status">
            <v-icon icon="mdi-check-circle-outline" size="16" /> {{ noticeMessage }}
          </p>

          <button class="submit-button" :aria-busy="busy" :aria-label="submitButtonLabel" :disabled="busy" type="submit">
            <v-progress-circular
              v-if="busy"
              indeterminate
              size="18"
              width="2"
            />

            <template v-else>
              <span>{{ submitButtonLabel }}</span>
              <v-icon icon="mdi-arrow-right" size="18" />
            </template>
          </button>
        </form>

        <button
          v-if="!isSignup"
          class="reset-link"
          type="button"
          @click="openPasswordReset"
        >{{ showPasswordResetForm ? 'Close password reset' : 'Forgot your password?' }}</button>

        <form
          v-if="!isSignup && showPasswordResetForm"
          class="password-reset-form"
          @submit.prevent="sendPasswordReset"
        >
          <label for="reset-email">Email for password reset</label>

          <input
            id="reset-email"
            v-model="resetEmail"
            autocomplete="email"
            required
            type="email"
          >

          <button class="secondary-submit-button" :disabled="resetBusy" type="submit">
            <v-progress-circular
              v-if="resetBusy"
              aria-label="Sending reset link"
              indeterminate
              size="16"
              width="2"
            />

            <template v-else>Send password reset link</template>
          </button>
        </form>

        <p class="mode-switch">
          {{ isSignup ? 'Already have an account?' : "Don't have an account?" }}
          <button :disabled="busy" type="button" @click="toggleMode">
            {{ isSignup ? 'Sign in' : 'Sign up' }}
          </button>
        </p>

      </section>
    </div>

    <footer class="login-footer container">
      <span>Internal clarity for external confidence.</span>
      <span>© 2025 Northstar Systems</span>
    </footer>
  </main>
</template>

<style scoped>
@import url("https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Manrope:wght@400;500;600;700;800&display=swap");

:global(*) {
  box-sizing: border-box;
}

:global(body) {
  margin: 0;
  background: #f3f5ef;
  color: #10231d;
  font-family: "Manrope", sans-serif;
}

.login-page {
  min-height: 100vh;
  background: #f3f5ef;
}

.container {
  width: min(1160px, calc(100% - 64px));
  margin: 0 auto;
}

.login-nav {
  height: 92px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid #d4ddd1;
}

.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  color: #18352d;
  text-decoration: none;
  font-size: 20px;
  font-weight: 800;
  letter-spacing: -1px;
}

.brand-mark {
  display: flex;
  align-items: end;
  gap: 2px;
  height: 20px;
}

.brand-mark span {
  display: block;
  width: 5px;
  background: #e16b4c;
}

.brand-mark span:nth-child(1) {
  height: 11px;
}

.brand-mark span:nth-child(2) {
  height: 17px;
}

.brand-mark span:nth-child(3) {
  height: 14px;
}

.brand-dot,
em {
  color: #e16b4c;
  font-style: normal;
}

.nav-note,
.section-overline,
.demo-label {
  color: #71897b;
  font: 10px "DM Mono", monospace;
  letter-spacing: 1.5px;
}

.login-layout {
  display: grid;
  grid-template-columns: 1fr 420px;
  gap: 120px;
  align-items: center;
  min-height: calc(100vh - 180px);
  padding: 75px 0;
}

.login-intro h1 {
  margin: 25px 0;
  color: #18352d;
  font-size: clamp(48px, 5.7vw, 78px);
  line-height: 0.99;
  letter-spacing: -4px;
}

.intro-copy {
  max-width: 390px;
  color: #6c7e73;
  font-size: 14px;
  line-height: 1.8;
}

.signal-list {
  display: grid;
  gap: 14px;
  margin-top: 48px;
  color: #18352d;
  font-size: 12px;
  font-weight: 700;
}

.signal-list span {
  display: flex;
  align-items: center;
  gap: 10px;
}

.signal-list .v-icon {
  color: #e16b4c;
}

.login-panel {
  padding: 42px;
  background: #18352d;
  color: #f3f5ef;
  box-shadow: 16px 18px 0 #dce7d5;
}

.panel-heading h2 {
  margin: 12px 0 30px;
  font-size: 35px;
  letter-spacing: -1.5px;
}

.login-panel .section-overline {
  color: #aabcae;
}

form {
  display: grid;
  gap: 10px;
}

label {
  margin-top: 10px;
  color: #bdcbbf;
  font-size: 11px;
  font-weight: 700;
}

input {
  width: 100%;
  border: 1px solid #557064;
  border-radius: 0;
  padding: 14px;
  background: #24473d;
  color: #f3f5ef;
  font: 13px "Manrope", sans-serif;
}

input::placeholder {
  color: #8da397;
}

input:focus {
  outline: 2px solid #d4ec66;
  outline-offset: 2px;
}

.password-field {
  position: relative;
  width: 100%;
}

.password-field input {
  padding-right: 50px;
}

.password-visibility-toggle {
  position: absolute;
  top: 0;
  right: 0;
  display: grid;
  width: 46px;
  height: 100%;
  place-items: center;
  border: 0;
  padding: 0;
  background: transparent;
  color: #d4ec66;
  cursor: pointer;
  opacity: 1;
  transition: color 120ms ease, background-color 120ms ease;
}

.password-visibility-toggle:hover {
  background: #31564a;
  color: #e5f38b;
}

.password-visibility-toggle:focus-visible {
  z-index: 1;
  border-radius: 2px;
  outline: 2px solid #e5f38b;
  outline-offset: -4px;
}

.error-message {
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 12px 0 0;
  color: #ffab91;
  font-size: 11px;
  line-height: 1.5;
}

.success-message {
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 12px 0 0;
  color: #d4ec66;
  font-size: 11px;
  line-height: 1.5;
}

.profile-retry {
  display: grid;
  gap: 8px;
  color: #ffab91;
  font-size: 10px;
  line-height: 1.5;
}

.profile-retry button {
  justify-self: start;
  border: 0;
  padding: 0;
  background: transparent;
  color: #d4ec66;
  cursor: pointer;
  font: 700 10px "Manrope", sans-serif;
}

.reset-link {
  display: block;
  margin: 15px auto 0;
  border: 0;
  padding: 0;
  background: transparent;
  color: #d4ec66;
  cursor: pointer;
  font: 600 10px "Manrope", sans-serif;
}

.submit-button {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 20px;
  border: 0;
  padding: 15px 18px;
  background: #d4ec66;
  color: #18352d;
  cursor: pointer;
  font: 700 12px "Manrope", sans-serif;
}

.submit-button:hover:not(:disabled) {
  background: #e5f38b;
}

.submit-button:disabled,
.secondary-submit-button:disabled,
.mode-switch button:disabled {
  cursor: wait;
  opacity: .7;
}

.password-reset-form {
  display: grid;
  gap: 8px;
  margin-top: 14px;
}

.password-reset-form label {
  color: #bdcbbf;
  font-size: 10px;
  font-weight: 700;
}

.password-reset-form input {
  min-height: 42px;
  border: 1px solid #557064;
  padding: 0 11px;
  background: #24473d;
  color: #f3f5ef;
  font: 12px "Manrope", sans-serif;
}

.secondary-submit-button {
  display: flex;
  min-height: 40px;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border: 1px solid #91a881;
  padding: 8px 12px;
  background: transparent;
  color: #d4ec66;
  cursor: pointer;
  font: 700 10px "Manrope", sans-serif;
}

.mode-switch {
  margin: 22px 0 0;
  color: #aabcae;
  font-size: 11px;
  text-align: center;
}

.mode-switch button {
  border: 0;
  padding: 0;
  background: transparent;
  color: #d4ec66;
  cursor: pointer;
  font: 700 11px "Manrope", sans-serif;
}

.mode-switch button:hover {
  color: #e5f38b;
}
.verification-link {
  display: inline-block;
  margin: 7px 0;
  color: #d4ec66;
  font-size: 10px;
  font-weight: 700;
  text-decoration: none;
}

.login-footer {
  display: flex;
  justify-content: space-between;
  padding: 20px 0 30px;
  border-top: 1px solid #d4ddd1;
  color: #82958a;
  font-size: 10px;
}

@media (max-width: 760px) {
  .container {
    width: min(100% - 40px, 520px);
  }

  .nav-note {
    display: none;
  }

  .login-layout {
    display: block;
    min-height: auto;
    padding: 58px 0 70px;
  }

  .login-intro h1 {
    font-size: clamp(46px, 14vw, 68px);
  }

  .login-panel {
    margin-top: 55px;
    padding: 30px 24px;
  }

  .login-footer {
    gap: 18px;
    flex-direction: column;
  }
}
</style>
