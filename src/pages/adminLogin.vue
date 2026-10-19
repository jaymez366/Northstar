<script setup lang="ts">
  import { onMounted, ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const router = useRouter()
  const email = ref('northstaradmin34@gmail.com')
  const password = ref('')
  const showPassword = ref(false)
  const busy = ref(false)
  const errorMessage = ref('')

  onMounted(async () => {
    await auth.initialize()
    if (auth.isAdmin) {
      await router.replace('/admin')
    }
  })

  async function signIn () {
    if (busy.value) return

    busy.value = true
    errorMessage.value = ''
    try {
      const authenticated = await auth.login(email.value.trim(), password.value)
      if (!authenticated) {
        errorMessage.value = auth.errorMessage || 'Unable to sign in to the Northstar Admin Portal.'
        return
      }

      if (!auth.isAdmin) {
        const signedOut = await auth.logout()
        errorMessage.value = signedOut
          ? 'This confirmed account is not authorized for the Northstar Admin Portal.'
          : `This account is not authorized for the Northstar Admin Portal. ${auth.errorMessage}`
        return
      }

      password.value = ''
      await router.replace('/admin')
    } finally {
      busy.value = false
    }
  }
</script>

<template>
  <main class="admin-login-page">
    <nav aria-label="Admin portal navigation" class="admin-login-nav">
      <router-link aria-label="Northstar home" class="admin-brand" to="/">
        <span class="brand-mark"><span /><span /><span /></span>
        <span>northstar<span class="brand-dot">.</span></span>
      </router-link>

      <router-link class="employee-login-link" to="/login">Employee sign in</router-link>
    </nav>

    <section aria-labelledby="admin-login-title" class="admin-login-card surface-card">
      <p class="eyebrow">SECURE ADMINISTRATION</p>
      <h1 id="admin-login-title">Northstar<br><em>Administration</em></h1>
      <p class="admin-login-copy">Sign in with the designated Northstar administrator account.</p>

      <form @submit.prevent="signIn">
        <label for="admin-email">Administrator email</label>

        <input
          id="admin-email"
          v-model="email"
          autocomplete="username"
          required
          type="email"
        >

        <label for="admin-password">Password</label>

        <div class="password-field">
          <input
            id="admin-password"
            v-model="password"
            autocomplete="current-password"
            required
            :type="showPassword ? 'text' : 'password'"
          >

          <button
            :aria-label="showPassword ? 'Hide password' : 'Show password'"
            :aria-pressed="showPassword"
            type="button"
            @click="showPassword = !showPassword"
          >
            <v-icon :icon="showPassword ? 'mdi-eye-off-outline' : 'mdi-eye-outline'" size="19" />
          </button>
        </div>

        <p v-if="errorMessage" class="admin-login-error" role="alert">{{ errorMessage }}</p>

        <button class="admin-submit" :disabled="busy" type="submit">
          <v-progress-circular
            v-if="busy"
            aria-label="Signing in"
            indeterminate
            size="18"
            width="2"
          />

          <span>{{ busy ? 'Signing in…' : 'Sign in to Admin Portal' }}</span>
          <v-icon v-if="!busy" icon="mdi-arrow-right" size="17" />
        </button>
      </form>

      <p class="security-note">
        <v-icon icon="mdi-shield-lock-outline" size="15" />
        Access is limited to the designated, email-confirmed administrator.
      </p>
    </section>
  </main>
</template>

<style scoped>
.admin-login-page {
  min-height: 100vh;
  padding: 0 24px 40px;
  background: var(--ns-bg-f3f5ef, #f3f5ef);
  color: var(--ns-text-10231d, #10231d);
  font-family: "Manrope", sans-serif;
}
.admin-login-nav {
  display: flex;
  max-width: 1160px;
  height: 82px;
  align-items: center;
  justify-content: space-between;
  margin: 0 auto;
  border-bottom: 1px solid var(--ns-border-dce4d8, #dce4d8);
}
.admin-brand {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--ns-text-18352d, #18352d);
  text-decoration: none;
  font-size: 20px;
  font-weight: 800;
  letter-spacing: -1px;
}
.brand-mark { display: flex; height: 20px; align-items: end; gap: 2px; }
.brand-mark span { display: block; width: 5px; background: var(--ns-bg-e16b4c, #e16b4c); }
.brand-mark span:nth-child(1) { height: 11px; }
.brand-mark span:nth-child(2) { height: 17px; }
.brand-mark span:nth-child(3) { height: 14px; }
.brand-dot { color: var(--ns-text-e16b4c, #e16b4c); }
.employee-login-link { color: var(--ns-text-60766a, #60766a); font-size: 12px; font-weight: 700; text-decoration: none; }
.admin-login-card {
  width: min(100%, 440px);
  margin: clamp(45px, 10vh, 100px) auto 0;
  padding: clamp(25px, 6vw, 42px);
}
.eyebrow { margin: 0 0 14px; color: var(--ns-text-71897b, #71897b); font: 10px "DM Mono", monospace; letter-spacing: 1.5px; }
h1 { margin: 0; color: var(--ns-text-18352d, #18352d); font-size: clamp(34px, 8vw, 46px); line-height: 1.05; letter-spacing: -2px; }
h1 em { color: var(--ns-text-e16b4c, #e16b4c); font-style: normal; }
.admin-login-copy { margin: 15px 0 25px; color: var(--ns-text-718178, #718178); font-size: 12px; line-height: 1.7; }
form { display: grid; gap: 9px; }
label { margin-top: 5px; color: var(--ns-text-52645a, #52645a); font-size: 10px; font-weight: 700; }
input {
  width: 100%;
  min-height: 43px;
  border: 1px solid var(--ns-border-dce4d8, #dce4d8);
  border-radius: 0;
  padding: 0 12px;
  background: var(--ns-bg-fff, #fff);
  color: var(--ns-text-18352d, #18352d);
  font: 12px "Manrope", sans-serif;
}
input:focus { border-color: var(--ns-border-71897b, #71897b); outline: 2px solid var(--ns-border-dce9c2, #dce9c2); }
.password-field { position: relative; }
.password-field input { padding-right: 44px; }
.password-field button {
  position: absolute;
  top: 0;
  right: 0;
  display: grid;
  width: 42px;
  height: 43px;
  place-items: center;
  border: 0;
  background: transparent;
  color: var(--ns-text-718178, #718178);
  cursor: pointer;
}
.admin-login-error { margin: 5px 0; color: var(--ns-text-a34c39, #a34c39); font-size: 11px; line-height: 1.6; }
.admin-submit {
  display: flex;
  min-height: 45px;
  align-items: center;
  justify-content: center;
  gap: 9px;
  margin-top: 9px;
  border: 0;
  background: var(--ns-bg-18352d, #18352d);
  color: var(--ns-text-f5f6ee, #f5f6ee);
  cursor: pointer;
  font: 700 11px "Manrope", sans-serif;
}
.admin-submit:disabled { cursor: wait; opacity: .7; }
.security-note { display: flex; align-items: flex-start; gap: 7px; margin: 19px 0 0; color: var(--ns-text-829187, #829187); font-size: 9px; line-height: 1.6; }
.security-note :deep(.v-icon) { flex: none; color: var(--ns-text-6e866f, #6e866f); }
@media (max-width: 480px) {
  .admin-login-page { padding-right: 16px; padding-left: 16px; }
  .admin-login-nav { height: 70px; }
}
</style>
