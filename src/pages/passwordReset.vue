<script setup lang="ts">
  import { onMounted, ref } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const route = useRoute()
  const router = useRouter()
  const password = ref('')
  const confirmPassword = ref('')
  const resetEmail = ref(typeof route.query.email === 'string' ? route.query.email : '')
  const errorMessage = ref('')
  const noticeMessage = ref('')
  const checkingSession = ref(true)
  const recoveryReady = ref(false)
  const busy = ref(false)
  const resendBusy = ref(false)

  onMounted(async () => {
    await auth.initialize()
    recoveryReady.value = auth.isAuthenticated && auth.isPasswordRecovery
    checkingSession.value = false
    if (!recoveryReady.value) {
      errorMessage.value = 'This password reset link is invalid or has expired. Request a new link to continue.'
    }
  })

  async function updatePassword () {
    if (busy.value) return
    errorMessage.value = ''
    noticeMessage.value = ''
    if (password.value.length < 8) {
      errorMessage.value = 'Your password must be at least 8 characters.'
      return
    }
    if (password.value !== confirmPassword.value) {
      errorMessage.value = 'Your passwords do not match.'
      return
    }
    busy.value = true
    try {
      if (await auth.updatePassword(password.value)) {
        await router.replace({ path: '/login', query: { reset: 'success' } })
      } else {
        errorMessage.value = auth.errorMessage
      }
    } finally {
      busy.value = false
    }
  }

  async function resendResetLink () {
    if (resendBusy.value) return
    errorMessage.value = ''
    noticeMessage.value = ''
    if (!resetEmail.value.trim()) {
      errorMessage.value = 'Enter the email address for your Northstar account.'
      return
    }

    resendBusy.value = true
    try {
      if (await auth.resetPassword(resetEmail.value.trim())) {
        noticeMessage.value = 'If an account exists for that address, a password reset link has been sent.'
      } else {
        errorMessage.value = auth.errorMessage
      }
    } finally {
      resendBusy.value = false
    }
  }
</script>

<template>
  <main class="reset-page">
    <router-link aria-label="Northstar home" class="brand" to="/">
      <span class="brand-mark"><span /><span /><span /></span>
      <span>northstar<span class="brand-dot">.</span></span>
    </router-link>

    <section class="reset-card">
      <p class="section-overline">ACCOUNT SECURITY</p>
      <h1>Choose a new<br><em>password.</em></h1>

      <p class="reset-copy">
        {{ recoveryReady ? 'Choose a strong password to secure your Northstar account.' : 'Use a valid password-reset link to continue.' }}
      </p>

      <p v-if="checkingSession" class="reset-copy" role="status">Checking your secure recovery session…</p>

      <form v-else-if="recoveryReady" @submit.prevent="updatePassword">
        <label for="new-password">New password</label>

        <input
          id="new-password"
          v-model="password"
          autocomplete="new-password"
          minlength="8"
          required
          type="password"
        >

        <label for="confirm-password">Confirm new password</label>

        <input
          id="confirm-password"
          v-model="confirmPassword"
          autocomplete="new-password"
          required
          type="password"
        >

        <p v-if="errorMessage" class="error-message" role="alert">{{ errorMessage }}</p>

        <button class="submit-button" :disabled="busy" type="submit">
          <v-progress-circular
            v-if="busy"
            aria-label="Updating password"
            indeterminate
            size="18"
            width="2"
          />

          <template v-else>Update password <v-icon icon="mdi-arrow-right" size="17" /></template>
        </button>
      </form>

      <form v-else @submit.prevent="resendResetLink">
        <label for="reset-email">Account email</label>

        <input
          id="reset-email"
          v-model="resetEmail"
          autocomplete="email"
          required
          type="email"
        >

        <p v-if="errorMessage" class="error-message" role="alert">{{ errorMessage }}</p>
        <p v-if="noticeMessage" class="success-message" role="status">{{ noticeMessage }}</p>

        <button class="submit-button" :disabled="resendBusy" type="submit">
          <v-progress-circular
            v-if="resendBusy"
            aria-label="Sending reset link"
            indeterminate
            size="18"
            width="2"
          />

          <template v-else>Request a new reset link <v-icon icon="mdi-email-fast-outline" size="17" /></template>
        </button>
      </form>

      <router-link class="return-link" to="/login">Return to sign in</router-link>
    </section>
  </main>
</template>

<style scoped>
.reset-page { display: grid; min-height: 100vh; grid-template-columns: 1fr minmax(320px, 480px) 1fr; align-items: start; gap: 28px; padding: 28px 5vw; background: var(--ns-bg-f3f5ef, #f3f5ef); color: var(--ns-text-18352d, #18352d); font-family: "Manrope", sans-serif; }
.brand { display: inline-flex; align-items: center; gap: 10px; color: var(--ns-text-18352d, #18352d); text-decoration: none; font-size: 20px; font-weight: 800; letter-spacing: -1px; }
.brand-mark { display: flex; align-items: end; gap: 2px; height: 20px; }
.brand-mark span { display: block; width: 5px; background: var(--ns-bg-e16b4c, #e16b4c); }
.brand-mark span:nth-child(1) { height: 11px; }
.brand-mark span:nth-child(2) { height: 17px; }
.brand-mark span:nth-child(3) { height: 14px; }
.brand-dot, em { color: var(--ns-text-e16b4c, #e16b4c); font-style: normal; }
.reset-card { grid-column: 2; margin-top: 15vh; padding: 36px; background: var(--ns-bg-18352d, #18352d); color: var(--ns-text-f3f5ef, #f3f5ef); box-shadow: 12px 14px 0 var(--ns-shadow-dce7d5, #dce7d5); }
.section-overline { color: var(--ns-text-aabcae, #aabcae); font: 10px "DM Mono", monospace; letter-spacing: 1.5px; }
.reset-card h1 { margin: 20px 0 12px; font-size: 42px; line-height: 1; letter-spacing: -2px; }
.reset-copy { margin: 0 0 24px; color: var(--ns-text-bdcbbf, #bdcbbf); font-size: 11px; line-height: 1.7; }
.reset-card form { display: grid; gap: 10px; }
label { margin-top: 8px; color: var(--ns-text-bdcbbf, #bdcbbf); font-size: 10px; font-weight: 700; }
input { width: 100%; border: 1px solid var(--ns-border-557064, #557064); padding: 13px; background: var(--ns-bg-24473d, #24473d); color: var(--ns-text-f3f5ef, #f3f5ef); font: 12px "Manrope", sans-serif; }
input:focus { outline: 2px solid var(--ns-border-d4ec66, #d4ec66); outline-offset: 2px; }
.error-message { color: var(--ns-text-ffab91, #ffab91); font-size: 10px; }
.submit-button { display: flex; align-items: center; justify-content: space-between; margin-top: 14px; border: 0; padding: 14px 16px; background: var(--ns-bg-d4ec66, #d4ec66); color: var(--ns-text-18352d, #18352d); cursor: pointer; font: 700 11px "Manrope", sans-serif; }
.submit-button:disabled { cursor: wait; opacity: .7; }
.error-message { color: var(--ns-text-ffab91, #ffab91); font-size: 10px; line-height: 1.6; }
.success-message { color: var(--ns-text-d4ec66, #d4ec66); font-size: 10px; line-height: 1.6; }
.return-link { display: block; margin-top: 20px; color: var(--ns-text-d4ec66, #d4ec66); text-align: center; text-decoration: none; font-size: 10px; }
@media (max-width: 760px) { .reset-page { display: block; padding: 20px; } .reset-card { margin: 12vh auto 0; padding: 28px 22px; } }
</style>
