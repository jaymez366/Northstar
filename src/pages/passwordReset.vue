<script setup lang="ts">
  import { ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const router = useRouter()
  const password = ref('')
  const confirmPassword = ref('')
  const errorMessage = ref('')

  async function updatePassword () {
    errorMessage.value = ''
    if (password.value.length < 8) {
      errorMessage.value = 'Your password must be at least 8 characters.'
      return
    }
    if (password.value !== confirmPassword.value) {
      errorMessage.value = 'Your passwords do not match.'
      return
    }
    if (await auth.updatePassword(password.value)) {
      router.replace('/overview')
    } else {
      errorMessage.value = auth.errorMessage
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
      <p class="reset-copy">Choose a strong password to secure your Northstar account.</p>

      <form @submit.prevent="updatePassword">
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
        <button class="submit-button" type="submit">Update password <v-icon icon="mdi-arrow-right" size="17" /></button>
      </form>

      <router-link class="return-link" to="/login">Return to sign in</router-link>
    </section>
  </main>
</template>

<style scoped>
.reset-page { display: grid; min-height: 100vh; grid-template-columns: 1fr minmax(320px, 480px) 1fr; align-items: start; gap: 28px; padding: 28px 5vw; background: #f3f5ef; color: #18352d; font-family: "Manrope", sans-serif; }
.brand { display: inline-flex; align-items: center; gap: 10px; color: #18352d; text-decoration: none; font-size: 20px; font-weight: 800; letter-spacing: -1px; }
.brand-mark { display: flex; align-items: end; gap: 2px; height: 20px; }
.brand-mark span { display: block; width: 5px; background: #e16b4c; }
.brand-mark span:nth-child(1) { height: 11px; }
.brand-mark span:nth-child(2) { height: 17px; }
.brand-mark span:nth-child(3) { height: 14px; }
.brand-dot, em { color: #e16b4c; font-style: normal; }
.reset-card { grid-column: 2; margin-top: 15vh; padding: 36px; background: #18352d; color: #f3f5ef; box-shadow: 12px 14px 0 #dce7d5; }
.section-overline { color: #aabcae; font: 10px "DM Mono", monospace; letter-spacing: 1.5px; }
.reset-card h1 { margin: 20px 0 12px; font-size: 42px; line-height: 1; letter-spacing: -2px; }
.reset-copy { margin: 0 0 24px; color: #bdcbbf; font-size: 11px; line-height: 1.7; }
.reset-card form { display: grid; gap: 10px; }
label { margin-top: 8px; color: #bdcbbf; font-size: 10px; font-weight: 700; }
input { width: 100%; border: 1px solid #557064; padding: 13px; background: #24473d; color: #f3f5ef; font: 12px "Manrope", sans-serif; }
input:focus { outline: 2px solid #d4ec66; outline-offset: 2px; }
.error-message { color: #ffab91; font-size: 10px; }
.submit-button { display: flex; align-items: center; justify-content: space-between; margin-top: 14px; border: 0; padding: 14px 16px; background: #d4ec66; color: #18352d; cursor: pointer; font: 700 11px "Manrope", sans-serif; }
.return-link { display: block; margin-top: 20px; color: #d4ec66; text-align: center; text-decoration: none; font-size: 10px; }
@media (max-width: 760px) { .reset-page { display: block; padding: 20px; } .reset-card { margin: 12vh auto 0; padding: 28px 22px; } }
</style>
