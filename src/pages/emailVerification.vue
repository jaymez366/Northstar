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
    } else if (auth.employeeRegistrationComplete && auth.profile.approvalStatus === 'approved') {
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
      message.value = 'If an account exists for this address and still needs confirmation, a new link will be sent. Northstar processes up to five confirmation resend requests per account in any 30-minute window. Once you reach that limit, further requests are paused until the window passes.'
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
        <p class="verification-copy">Use the confirmation link sent to your work email to activate your account. Once confirmed, return to Northstar to sign in.</p>
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
          {{ busy ? 'Sending…' : 'Resend confirmation email' }}
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
  background: #f3f5ef;
  color: #10231d;
  font-family: "Manrope", sans-serif;
}
.verification-nav {
  display: flex;
  max-width: 1160px;
  height: 82px;
  align-items: center;
  justify-content: space-between;
  margin: 0 auto;
  border-bottom: 1px solid #d4ddd1;
  color: #82958a;
  font: 9px "DM Mono", monospace;
  letter-spacing: 1px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  color: #18352d;
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
  background: #526c5c;
}
.brand-mark span:nth-child(1) { height: 11px; }
.brand-mark span:nth-child(2) { height: 17px; }
.brand-mark span:nth-child(3) { height: 14px; }
.brand-dot { color: #e16b4c; }
.verification-card {
  width: min(100%, 470px);
  margin: 72px auto;
  border: 1px solid #e0e6dc;
  padding: clamp(25px, 6vw, 44px);
  background: #fff;
  box-shadow: 12px 16px 0 rgba(16, 45, 38, 0.06);
}
.eyebrow {
  color: #758b7c;
  font: 9px "DM Mono", monospace;
  letter-spacing: 1.5px;
}
h1 {
  margin: 16px 0;
  color: #18352d;
  font-size: clamp(31px, 7vw, 44px);
  line-height: 1.06;
  letter-spacing: -2px;
}
h1 em { color: #e16b4c; font-style: normal; }
.verification-copy {
  margin: 0 0 25px;
  color: #718178;
  font-size: 12px;
  line-height: 1.7;
}
form { display: grid; gap: 9px; }
label {
  margin-top: 9px;
  color: #53665a;
  font-size: 10px;
  font-weight: 700;
}
input {
  width: 100%;
  min-height: 43px;
  border: 1px solid #dce4d9;
  border-radius: 0;
  padding: 0 12px;
  background: #fbfcf9;
  color: #18352d;
  font: 12px "Manrope", sans-serif;
}
.primary-action {
  display: flex;
  min-height: 45px;
  align-items: center;
  justify-content: center;
  gap: 10px;
  border: 0;
  padding: 10px 16px;
  background: #18352d;
  color: #f5f6ee;
  cursor: pointer;
  font: 700 11px "Manrope", sans-serif;
}
.primary-action:disabled,
.primary-action:disabled { cursor: wait; opacity: .6; }
.verify-button { margin-top: 9px; }
.continue-link { text-decoration: none; }
.form-error, .form-message { margin: 5px 0; font-size: 10px; line-height: 1.6; }
.form-error { color: #a34c39; }
.form-message { color: #4b8058; }
.return-link {
  border: 0;
  padding: 0;
  background: transparent;
  color: #526c5c;
  cursor: pointer;
  font: 700 10px "Manrope", sans-serif;
  display: inline-block;
  margin-top: 22px;
  color: #829187;
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
