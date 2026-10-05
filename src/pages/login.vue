<script setup lang="ts">
  import { ref } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const route = useRoute()
  const router = useRouter()
  const isSignup = ref(false)
  const fullName = ref('')
  const email = ref('')
  const password = ref('')
  const confirmPassword = ref('')
  const errorMessage = ref('')

  function submitForm () {
    errorMessage.value = ''

    if (isSignup.value) {
      if (password.value.length < 8) {
        errorMessage.value = 'Your password must be at least 8 characters.'
        return
      }

      if (password.value !== confirmPassword.value) {
        errorMessage.value = 'Your passwords do not match.'
        return
      }

      auth.signup(email.value.trim(), password.value)
    } else if (!auth.login(email.value.trim(), password.value)) {
      errorMessage.value = 'That email or password is not recognized.'
      return
    }

    const redirect = typeof route.query.redirect === 'string'
      ? route.query.redirect
      : '/'

    router.push(redirect)
  }

  function toggleMode () {
    isSignup.value = !isSignup.value
    errorMessage.value = ''
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

          <input
            id="password"
            v-model="password"
            autocomplete="current-password"
            placeholder="Enter your password"
            required
            type="password"
          >

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

          <p v-if="errorMessage" class="error-message" role="alert">
            <v-icon icon="mdi-alert-circle-outline" size="16" /> {{ errorMessage }}
          </p>

          <button class="submit-button" type="submit">
            {{ isSignup ? 'Create account' : 'Enter workspace' }}
            <v-icon icon="mdi-arrow-right" size="18" />
          </button>
        </form>

        <p class="mode-switch">
          {{ isSignup ? 'Already have an account?' : "Don't have an account?" }}
          <button type="button" @click="toggleMode">
            {{ isSignup ? 'Sign in' : 'Sign up' }}
          </button>
        </p>

        <div v-if="!isSignup" class="demo-note">
          <span class="demo-label">DEMO ACCOUNT</span>
          <strong>demo@northstar.com</strong>
          <span>Password: northstar123</span>
        </div>
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

:global(*) { box-sizing: border-box; }
:global(body) {
  margin: 0;
  background: #f3f5ef;
  color: #10231d;
  font-family: "Manrope", sans-serif;
}
.login-page { min-height: 100vh; background: #f3f5ef; }
.container { width: min(1160px, calc(100% - 64px)); margin: 0 auto; }
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
.brand-mark { display: flex; align-items: end; gap: 2px; height: 20px; }
.brand-mark span { display: block; width: 5px; background: #e16b4c; }
.brand-mark span:nth-child(1) { height: 11px; }
.brand-mark span:nth-child(2) { height: 17px; }
.brand-mark span:nth-child(3) { height: 14px; }
.brand-dot, em { color: #e16b4c; font-style: normal; }
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
.intro-copy { max-width: 390px; color: #6c7e73; font-size: 14px; line-height: 1.8; }
.signal-list { display: grid; gap: 14px; margin-top: 48px; color: #18352d; font-size: 12px; font-weight: 700; }
.signal-list span { display: flex; align-items: center; gap: 10px; }
.signal-list .v-icon { color: #e16b4c; }
.login-panel { padding: 42px; background: #18352d; color: #f3f5ef; box-shadow: 16px 18px 0 #dce7d5; }
.panel-heading h2 { margin: 12px 0 30px; font-size: 35px; letter-spacing: -1.5px; }
.login-panel .section-overline { color: #aabcae; }
form { display: grid; gap: 10px; }
label { margin-top: 10px; color: #bdcbbf; font-size: 11px; font-weight: 700; }
input { width: 100%; border: 1px solid #557064; border-radius: 0; padding: 14px; background: #24473d; color: #f3f5ef; font: 13px "Manrope", sans-serif; }
input::placeholder { color: #8da397; }
input:focus { outline: 2px solid #d4ec66; outline-offset: 2px; }
.error-message { display: flex; align-items: center; gap: 7px; margin: 12px 0 0; color: #ffab91; font-size: 11px; line-height: 1.5; }
.submit-button { display: flex; align-items: center; justify-content: space-between; margin-top: 20px; border: 0; padding: 15px 18px; background: #d4ec66; color: #18352d; cursor: pointer; font: 700 12px "Manrope", sans-serif; }
.submit-button:hover { background: #e5f38b; }
.mode-switch { margin: 22px 0 0; color: #aabcae; font-size: 11px; text-align: center; }
.mode-switch button { border: 0; padding: 0; background: transparent; color: #d4ec66; cursor: pointer; font: 700 11px "Manrope", sans-serif; }
.mode-switch button:hover { color: #e5f38b; }
.demo-note { display: grid; gap: 6px; margin-top: 28px; padding-top: 20px; border-top: 1px solid #3c5c51; color: #aabcae; font-size: 11px; }
.demo-note strong { color: #f3f5ef; font-size: 12px; }
.demo-label { color: #d4ec66; }
.login-footer { display: flex; justify-content: space-between; padding: 20px 0 30px; border-top: 1px solid #d4ddd1; color: #82958a; font-size: 10px; }
@media (max-width: 760px) {
  .container { width: min(100% - 40px, 520px); }
  .nav-note { display: none; }
  .login-layout { display: block; min-height: auto; padding: 58px 0 70px; }
  .login-intro h1 { font-size: clamp(46px, 14vw, 68px); }
  .login-panel { margin-top: 55px; padding: 30px 24px; }
  .login-footer { gap: 18px; flex-direction: column; }
}
</style>
