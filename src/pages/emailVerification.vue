<script setup lang="ts">
  import { onMounted, ref } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const route = useRoute()
  const router = useRouter()
  const email = ref(typeof route.query.email === 'string' ? route.query.email : '')
  const busy = ref(false)
  const message = ref('')
  const error = ref('')
  const callbackState = ref<'idle' | 'checking' | 'success' | 'error'>('idle')
  const isCallback = route.path === '/auth/callback'

  onMounted(() => {
    if (isCallback) {
      void handleConfirmationCallback()
    }
  })

  async function handleConfirmationCallback () {
    callbackState.value = 'checking'
    error.value = ''
    message.value = ''
    await auth.initialize()

    const hashParams = new URLSearchParams(window.location.hash.slice(1))
    const queryError = route.query.error_description ?? route.query.error
    const callbackError = String(queryError ?? hashParams.get('error_description') ?? hashParams.get('error') ?? '')
    if (callbackError) {
      callbackState.value = 'error'
      error.value = 'This confirmation link is invalid or has expired. Request a new confirmation email and try again.'
      return
    }

    if (!auth.isAuthenticated || !auth.emailVerified) {
      callbackState.value = 'error'
      error.value = 'We could not confirm your email. The link may have expired or already been used. You can request a new confirmation email below.'
      return
    }

    email.value = auth.userEmail
    await auth.refreshProfile()
    callbackState.value = 'success'
    message.value = 'Your email has been verified successfully.'

    let destination = '/pending-approval'
    if (auth.isAdmin) {
      destination = '/admin'
    } else if (auth.employeeRegistrationComplete && auth.canAccessEmployeeWorkspace) {
      destination = '/overview'
    } else if (!auth.employeeRegistrationComplete) {
      destination = '/employee-registration'
    }
    await router.replace(destination)
  }

  async function resendConfirmation () {
    error.value = ''
    message.value = ''
    if (!email.value.trim()) {
      error.value = 'Enter the email address you used to create your Northstar account.'
      return
    }
    busy.value = true
    try {
      const sent = await auth.resendSignupConfirmation(email.value.trim())
      if (!sent) {
        error.value = auth.errorMessage
        return
      }
      message.value = `A verification link was requested for ${email.value.trim()}. Click the link to verify your email. Northstar processes up to five confirmation resend requests per account in any 30-minute window. Once you reach that limit, further requests are paused until the window passes.`
    } finally {
      busy.value = false
    }
  }
</script>

<template>
  <main class="verification-page">
    <nav aria-label="Main navigation" class="verification-nav">
      <router-link aria-label="Northstar home" class="brand" to="/">
        <span class="brand-mark"><span /><span /><span /></span>
        <span>northstar<span class="brand-dot">.</span></span>
      </router-link>

      <span>SECURE WORKSPACE ACCESS</span>
    </nav>

    <section aria-labelledby="verification-title" class="verification-card">
      <p class="eyebrow">EMAIL VERIFICATION</p>

      <template v-if="isCallback">
        <template v-if="callbackState === 'checking'">
          <h1 id="verification-title">Confirming your<br><em>Northstar email.</em></h1>
          <p class="verification-copy" role="status">Checking your confirmation link with Supabase…</p>
        </template>

        <template v-else-if="callbackState === 'success'">
          <h1 id="verification-title">Email verified<br><em>successfully.</em></h1>
          <p class="verification-copy" role="status">{{ message }}</p>

          <router-link class="primary-action verify-button continue-link" to="/login">
            Continue to Northstar
            <v-icon icon="mdi-arrow-right" size="17" />
          </router-link>
        </template>

        <template v-else>
          <h1 id="verification-title">Confirmation link<br><em>not verified.</em></h1>
          <p class="verification-copy">The link may be invalid, expired, or already used. You can request a new confirmation email below.</p>
        </template>
      </template>

      <template v-else>
        <h1 id="verification-title">Check your<br><em>Northstar email.</em></h1>
        <p class="verification-copy">Use the confirmation link sent to <strong>{{ email || 'your work email' }}</strong> to activate your account. Click the link before returning to Northstar to sign in.</p>
      </template>

      <form v-if="!isCallback || callbackState === 'error'" @submit.prevent="resendConfirmation">
        <label for="confirmation-email">Work email</label>

        <input
          id="confirmation-email"
          v-model="email"
          autocomplete="email"
          required
          type="email"
        >

        <p v-if="error" class="form-error" role="alert">{{ error }}</p>
        <p v-if="message && callbackState !== 'success'" class="form-message" role="status">{{ message }}</p>

        <button class="primary-action verify-button" :disabled="busy" type="submit">
          {{ busy ? 'Sending verification email…' : 'Resend confirmation email' }}
          <v-icon v-if="busy" class="rotate-icon" icon="mdi-loading" size="17" />
          <v-icon v-else icon="mdi-email-fast-outline" size="17" />
        </button>
      </form>

      <router-link class="return-link" to="/login">Return to sign in</router-link>
    </section>
  </main>
</template>

<style scoped>
.verification-page {
  min-height: 100vh;
  padding: 0 24px;
  background: var(--ns-bg-f3f5ef, #f3f5ef);
  color: var(--ns-text-10231d, #10231d);
  font-family: "Manrope", sans-serif;
}
.verification-nav {
  display: flex;
  max-width: 1160px;
  height: 82px;
  align-items: center;
  justify-content: space-between;
  margin: 0 auto;
  border-bottom: 1px solid var(--ns-border-d4ddd1, #d4ddd1);
  color: var(--ns-text-82958a, #82958a);
  font: 9px "DM Mono", monospace;
  letter-spacing: 1px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--ns-text-18352d, #18352d);
  font: 800 20px "Manrope", sans-serif;
  letter-spacing: -1px;
  text-decoration: none;
}
.brand-mark {
  display: flex;
  height: 20px;
  align-items: end;
  gap: 2px;
}
.brand-mark span {
  width: 5px;
  background: var(--ns-bg-526c5c, #526c5c);
}
.brand-mark span:nth-child(1) { height: 11px; }
.brand-mark span:nth-child(2) { height: 17px; }
.brand-mark span:nth-child(3) { height: 14px; }
.brand-dot { color: var(--ns-text-e16b4c, #e16b4c); }
.verification-card {
  width: min(100%, 470px);
  margin: 72px auto;
  border: 1px solid var(--ns-border-e0e6dc, #e0e6dc);
  padding: clamp(25px, 6vw, 44px);
  background: var(--ns-bg-fff, #fff);
  border-radius: 16px;
  box-shadow: 0 20px 52px rgb(15 23 42 / 8%);
}
.eyebrow {
  color: var(--ns-text-758b7c, #758b7c);
  font: 9px "DM Mono", monospace;
  letter-spacing: 1.5px;
}
h1 {
  margin: 16px 0;
  color: var(--ns-text-18352d, #18352d);
  font-size: clamp(31px, 7vw, 44px);
  line-height: 1.06;
  letter-spacing: -2px;
}
h1 em { color: var(--ns-text-e16b4c, #e16b4c); font-style: normal; }
.verification-copy {
  margin: 0 0 25px;
  color: var(--ns-text-718178, #718178);
  font-size: 12px;
  line-height: 1.7;
}
form { display: grid; gap: 9px; }
label {
  margin-top: 9px;
  color: var(--ns-text-53665a, #53665a);
  font-size: 10px;
  font-weight: 700;
}
input {
  width: 100%;
  min-height: 43px;
  border: 1px solid var(--ns-border-dce4d9, #dce4d9);
  border-radius: 0;
  padding: 0 12px;
  background: var(--ns-bg-fbfcf9, #fbfcf9);
  color: var(--ns-text-18352d, #18352d);
  font: 12px "Manrope", sans-serif;
  border-radius: 8px;
}
input:focus { border-color: var(--ns-primary); outline: 3px solid color-mix(in srgb, var(--ns-primary) 18%, transparent); outline-offset: 1px; }
.primary-action {
  display: flex;
  min-height: 45px;
  align-items: center;
  justify-content: center;
  gap: 10px;
  border: 0;
  padding: 10px 16px;
  background: var(--ns-bg-18352d, #18352d);
  color: var(--ns-text-f5f6ee, #f5f6ee);
  cursor: pointer;
  font: 700 11px "Manrope", sans-serif;
}
.primary-action:disabled,
.primary-action:disabled { cursor: wait; opacity: .6; }
.primary-action { border-radius: 8px; background: var(--ns-primary); }
.primary-action:hover:not(:disabled) { background: var(--ns-primary-hover); }
.primary-action:focus-visible, .return-link:focus-visible { outline: 3px solid var(--ns-blue-border); outline-offset: 2px; }
.verify-button { margin-top: 9px; }
.continue-link { text-decoration: none; }
.form-error, .form-message { margin: 5px 0; font-size: 10px; line-height: 1.6; }
.form-error { color: var(--ns-text-a34c39, #a34c39); }
.form-message { color: var(--ns-text-4b8058, #4b8058); }
.return-link {
  border: 0;
  padding: 0;
  background: transparent;
  color: var(--ns-text-526c5c, #526c5c);
  cursor: pointer;
  font: 700 10px "Manrope", sans-serif;
  display: inline-block;
  margin-top: 22px;
  color: var(--ns-text-829187, #829187);
  text-decoration: none;
}
.rotate-icon { animation: rotate 1s linear infinite; }
@keyframes rotate { to { transform: rotate(360deg); } }
@media (max-width: 480px) {
  .verification-page { padding: 0 16px; }
  .verification-nav { height: 70px; }
  .verification-card { margin: 38px auto; }
}
@media (prefers-reduced-motion: reduce) {
  .rotate-icon { animation: none; }
}
</style>
