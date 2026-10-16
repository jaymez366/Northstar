<script setup lang="ts">
  import { onMounted, watch } from 'vue'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const router = useRouter()

  onMounted(() => {
    void ensureAdminSession()
  })

  watch(() => [auth.isAuthenticated, auth.isAdmin], ([isAuthenticated, isAdmin]) => {
    if (!isAuthenticated || !isAdmin) {
      void router.replace('/admin-login')
    }
  })

  async function ensureAdminSession () {
    await auth.initialize()
    if (!auth.isAuthenticated || !auth.isAdmin) {
      await router.replace('/admin-login')
      return
    }
  }

  async function logout () {
    if (await auth.logout()) {
      await router.replace('/admin-login')
    }
  }
</script>

<template>
  <div class="admin-shell">
    <header class="admin-topbar">
      <router-link aria-label="Northstar Admin Portal home" class="admin-brand" to="/admin">
        <span class="brand-mark"><span /><span /><span /></span>
        <span>northstar<span class="brand-dot">.</span></span>
        <span class="portal-label">ADMINISTRATION</span>
      </router-link>

      <div class="admin-topbar-actions">
        <v-menu location="bottom end">
          <template #activator="{ props }">
            <button v-bind="props" class="admin-profile-button" type="button">
              <span class="admin-avatar">{{ (auth.userEmail[0] || 'A').toUpperCase() }}</span>

              <span class="admin-profile-copy">
                <strong>Administrator</strong>
                <small>{{ auth.userEmail }}</small>
              </span>

              <v-icon icon="mdi-chevron-down" size="17" />
            </button>
          </template>

          <v-list class="admin-menu-list" density="compact">
            <v-list-item subtitle="Signed in administrator" :title="auth.userEmail" />
            <v-list-item prepend-icon="mdi-logout" title="Sign out" @click="logout" />
          </v-list>
        </v-menu>
      </div>
    </header>

    <main class="admin-content">
      <v-alert
        v-if="auth.errorMessage"
        class="admin-data-alert"
        closable
        type="warning"
        variant="tonal"
        @click:close="auth.errorMessage = ''"
      >
        {{ auth.errorMessage }}
      </v-alert>

      <slot />
    </main>
  </div>
</template>

<style scoped>
.admin-shell { min-height: 100vh; background: #f3f5ef; color: #10231d; }
.admin-topbar {
  position: sticky;
  z-index: 5;
  top: 0;
  display: flex;
  min-height: 72px;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  padding: 0 max(24px, calc((100vw - 1240px) / 2));
  border-bottom: 1px solid #dce4d8;
  background: #fff;
}
.admin-brand { display: flex; align-items: center; gap: 9px; color: #18352d; text-decoration: none; font-size: 19px; font-weight: 800; letter-spacing: -1px; }
.brand-mark { display: flex; height: 19px; align-items: end; gap: 2px; }
.brand-mark span { display: block; width: 5px; background: #e16b4c; }
.brand-mark span:nth-child(1) { height: 10px; }
.brand-mark span:nth-child(2) { height: 16px; }
.brand-mark span:nth-child(3) { height: 13px; }
.brand-dot { color: #e16b4c; }
.portal-label { margin-left: 7px; padding-left: 14px; border-left: 1px solid #dce4d8; color: #71897b; font: 9px "DM Mono", monospace; letter-spacing: 1px; }
.admin-topbar-actions { display: flex; align-items: center; gap: 10px; }
.admin-icon-button { position: relative; display: grid; width: 40px; height: 40px; place-items: center; border: 1px solid #e3e9df; background: #fff; color: #52645a; cursor: pointer; }
.notification-count { position: absolute; top: -5px; right: -5px; display: grid; min-width: 16px; height: 16px; place-items: center; border-radius: 9px; padding: 0 4px; background: #e16b4c; color: #fff; font-size: 8px; }
.admin-profile-button { display: flex; align-items: center; gap: 9px; border: 0; background: transparent; color: #18352d; cursor: pointer; text-align: left; }
.admin-avatar { display: grid; width: 34px; height: 34px; place-items: center; border-radius: 50%; background: #eaf3bd; color: #526738; font-size: 12px; font-weight: 800; }
.admin-profile-copy { display: grid; gap: 3px; }
.admin-profile-copy strong { font-size: 10px; }
.admin-profile-copy small { color: #829187; font-size: 9px; }
.admin-menu-list { max-width: min(360px, calc(100vw - 24px)); }
.admin-content { width: min(1240px, calc(100% - 48px)); margin: 0 auto; padding: 26px 0 40px; }
.admin-data-alert { margin-bottom: 16px; }
@media (max-width: 600px) {
  .admin-topbar { min-height: 64px; padding: 0 14px; }
  .portal-label { display: none; }
  .admin-profile-copy { display: none; }
  .admin-topbar-actions { gap: 7px; }
  .admin-content { width: calc(100% - 28px); padding-top: 18px; }
}
</style>
