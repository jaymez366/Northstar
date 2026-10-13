<script setup lang="ts">
  import { ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const router = useRouter()
  const checking = ref(false)
  const error = ref('')

  async function checkStatus () {
    checking.value = true
    error.value = ''
    await auth.refreshProfile()
    checking.value = false
    if (auth.profile.approvalStatus === 'approved' || auth.profile.role === 'admin') {
      await router.replace('/overview')
    } else if (!auth.profile.registrationCompleted) {
      await router.replace('/employee-registration')
    } else if (auth.errorMessage) {
      error.value = auth.errorMessage
    }
  }

  async function signOut () {
    if (await auth.logout()) {
      await router.replace('/login')
    } else {
      error.value = auth.errorMessage
    }
  }
</script>

<template>
  <main class="approval-page">
    <section class="approval-card surface-card">
      <span class="approval-icon"><v-icon icon="mdi-account-clock-outline" size="25" /></span>
      <p class="eyebrow">REGISTRATION RECEIVED</p>
      <h1>You're almost<br><em>in the Northstar.</em></h1>

      <p class="approval-copy">
        <template v-if="auth.profile.approvalStatus === 'rejected'">
          An administrator could not approve this registration. Please contact your Northstar administrator for next steps.
        </template>

        <template v-else>
          Your email is verified and your employee details have been submitted.
          Workspace access will be enabled after an administrator reviews your registration.
        </template>
      </p>

      <p class="approval-state" :class="{ rejected: auth.profile.approvalStatus === 'rejected' }">
        <i /> {{ auth.profile.approvalStatus === 'rejected' ? 'Registration not approved' : 'Awaiting administrator approval' }}
      </p>

      <p v-if="error" class="approval-error" role="alert">{{ error }}</p>

      <div class="approval-actions">
        <button class="primary-action" :disabled="checking" type="button" @click="checkStatus">
          {{ checking ? 'Checking…' : 'Check approval status' }}
          <v-icon icon="mdi-refresh" size="16" />
        </button>

        <button class="secondary-action" type="button" @click="signOut">Sign out</button>
      </div>
    </section>
  </main>
</template>

<style scoped>
.approval-page { display: grid; min-height: 62vh; place-items: center; padding: 20px; }
.approval-card { width: min(100%, 550px); padding: clamp(24px, 5vw, 40px); }
.approval-icon { display: grid; width: 48px; height: 48px; place-items: center; background: #f8e8df; color: #b8583e; }
.eyebrow { margin: 23px 0 10px; color: #758b7c; font: 9px "DM Mono", monospace; letter-spacing: 1.5px; }
h1 { margin: 0; color: #18352d; font-size: clamp(34px, 6vw, 48px); line-height: 1.03; letter-spacing: -2px; }
h1 em { color: #e16b4c; font-style: normal; }
.approval-copy { max-width: 410px; margin: 16px 0; color: #718178; font-size: 11px; line-height: 1.8; }
.approval-state { display: flex; align-items: center; gap: 8px; color: #9b7049; font-size: 10px; }
.approval-state i { width: 7px; height: 7px; border-radius: 50%; background: #d79354; }
.approval-state.rejected { color: #a34c39; }
.approval-state.rejected i { background: #b85138; }
.approval-error { color: #a34c39; font-size: 10px; }
.approval-actions { display: flex; flex-wrap: wrap; gap: 9px; margin-top: 23px; }
.approval-actions button { min-height: 39px; font-size: 9px; }
</style>
