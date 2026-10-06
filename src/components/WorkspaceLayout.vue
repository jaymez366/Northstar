<script setup lang="ts">
  import { onMounted, onUnmounted } from 'vue'
  import { useRouter } from 'vue-router'
  import GlobalSearch from '@/components/GlobalSearch.vue'
  import { useAuthStore } from '@/stores/auth'
  import { useWorkspaceStore } from '@/stores/workspace'

  const auth = useAuthStore()
  const workspace = useWorkspaceStore()
  const router = useRouter()

  const primaryLinks = [
    { title: 'Overview', to: '/overview', icon: 'mdi-view-dashboard-outline' },
    { title: 'Messages', to: '/messages', icon: 'mdi-message-text-outline' },
    { title: 'Announcements', to: '/announcements', icon: 'mdi-bullhorn-outline' },
    { title: 'Employees', to: '/employees', icon: 'mdi-account-group-outline' },
    { title: 'Departments', to: '/departments', icon: 'mdi-domain' },
    { title: 'Events', to: '/events', icon: 'mdi-calendar-month-outline' },
    { title: 'Resources', to: '/resources', icon: 'mdi-folder-outline' },
  ]

  async function logout () {
    if (await auth.logout()) {
      router.push('/login')
    }
  }

  onMounted(() => {
    void workspace.load()
    workspace.subscribeToMessages()
  })

  onUnmounted(() => workspace.unsubscribeFromMessages())
</script>

<template>
  <div class="workspace-shell">
    <aside class="sidebar">
      <router-link aria-label="Northstar home" class="brand" to="/">
        <span class="brand-mark"><span /><span /><span /></span>
        <span>northstar<span class="brand-dot">.</span></span>
      </router-link>

      <p class="nav-label">WORKSPACE</p>

      <nav aria-label="Workspace navigation" class="side-nav">
        <router-link
          v-for="link in primaryLinks"
          :key="link.to"
          active-class="active"
          :to="link.to"
        >
          <v-icon :icon="link.icon" size="19" />
          <span>{{ link.title }}</span>
        </router-link>

        <router-link active-class="active" to="/notifications">
          <v-icon icon="mdi-bell-outline" size="19" />
          <span>Notifications</span>
          <span v-if="workspace.unreadNotifications" class="unread-count">{{ workspace.unreadNotifications }}</span>
        </router-link>
      </nav>

      <div class="sidebar-bottom">
        <router-link active-class="active" to="/profile">
          <v-icon icon="mdi-account-circle-outline" size="19" />
          <span>Profile</span>
        </router-link>

        <router-link active-class="active" to="/settings">
          <v-icon icon="mdi-cog-outline" size="19" />
          <span>Settings</span>
        </router-link>

        <router-link v-if="auth.isAdmin" active-class="active" to="/admin">
          <v-icon icon="mdi-shield-account-outline" size="19" />
          <span>Admin dashboard</span>
        </router-link>

        <button class="logout-button" type="button" @click="logout">
          <v-icon icon="mdi-logout" size="19" />
          <span>Sign out</span>
        </button>
      </div>
    </aside>

    <div class="workspace-column">
      <header class="topbar">
        <GlobalSearch />

        <div class="topbar-actions">
          <router-link aria-label="Notifications" class="notification-button" to="/notifications">
            <v-icon icon="mdi-bell-outline" size="21" />
            <span v-if="workspace.unreadNotifications" class="notification-dot" />
          </router-link>

          <router-link class="user-summary" to="/profile">
            <span class="user-avatar" :style="auth.profile.photoUrl ? { backgroundImage: `url(${auth.profile.photoUrl})` } : undefined">{{ !auth.profile.photoUrl && (auth.profile.firstName || auth.userFirstName || 'U').charAt(0).toUpperCase() }}</span>
            <span><strong>{{ auth.profile.firstName || auth.userFirstName }}</strong><small>{{ auth.profile.jobTitle || 'Northstar member' }}</small></span>
          </router-link>
        </div>
      </header>

      <main class="workspace-main">      <v-alert
                                           v-if="workspace.backendError || auth.errorMessage"
                                           class="backend-alert"
                                           closable
                                           type="warning"
                                           variant="tonal"
                                           @click:close="workspace.backendError = ''; auth.errorMessage = ''"
                                         >
                                           {{ workspace.backendError || auth.errorMessage }}
                                           <template #append>
                                             <v-btn size="small" variant="text" @click="workspace.load">Retry</v-btn>
                                           </template>
                                         </v-alert>

        <slot /></main>
    </div>
  </div>
</template>

<style>
@import url("https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Manrope:wght@400;500;600;700;800&display=swap");

:root {
  font-family: "Manrope", sans-serif;
  color: #10231d;
  background: #f3f5ef;
  font-synthesis: none;
}
* { box-sizing: border-box; }
body { min-width: 320px; margin: 0; background: #f3f5ef; }
.v-application, .v-main { background: #f3f5ef !important; color: #10231d; }
.workspace-shell { min-height: 100vh; }
.sidebar {
  position: fixed;
  z-index: 10;
  inset: 0 auto 0 0;
  display: flex;
  width: 232px;
  flex-direction: column;
  padding: 26px 16px 18px;
  background: #102d26;
  color: #f5f6ee;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 10px;
  color: inherit;
  text-decoration: none;
  font-size: 20px;
  font-weight: 800;
  letter-spacing: -1px;
}
.brand-mark { display: flex; align-items: end; gap: 2px; height: 20px; }
.brand-mark span { display: block; width: 5px; background: #d4ec66; }
.brand-mark span:nth-child(1) { height: 11px; }
.brand-mark span:nth-child(2) { height: 17px; }
.brand-mark span:nth-child(3) { height: 14px; }
.brand-dot { color: #d4ec66; }
.nav-label {
  margin: 48px 10px 12px;
  color: #82998b;
  font: 9px "DM Mono", monospace;
  letter-spacing: 1.5px;
}
.side-nav, .sidebar-bottom { display: grid; gap: 4px; }
.side-nav a, .sidebar-bottom a, .logout-button {
  display: flex;
  min-height: 41px;
  align-items: center;
  gap: 12px;
  border: 0;
  padding: 0 11px;
  background: transparent;
  color: #bac9bd;
  cursor: pointer;
  text-align: left;
  text-decoration: none;
  font: 500 11px "Manrope", sans-serif;
}
.side-nav a:hover, .sidebar-bottom a:hover, .logout-button:hover,
.side-nav a.active, .sidebar-bottom a.active {
  background: #1d4035;
  color: #d4ec66;
}
.side-nav a.active { box-shadow: inset 2px 0 #d4ec66; }
.unread-count { margin-left: auto; color: #d4ec66; font-size: 10px; }
.sidebar-bottom { margin-top: auto; padding-top: 16px; border-top: 1px solid #ffffff1c; }
.workspace-column { min-height: 100vh; margin-left: 232px; }
.topbar {
  position: sticky;
  z-index: 8;
  top: 0;
  display: flex;
  height: 72px;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  padding: 0 34px;
  border-bottom: 1px solid #dce4d8;
  background: #f9faf6ed;
  backdrop-filter: blur(12px);
}
.topbar-actions { display: flex; align-items: center; gap: 22px; }
.notification-button { position: relative; color: #526c5c; }
.notification-dot { position: absolute; top: 1px; right: 0; width: 7px; height: 7px; border: 1px solid #f9faf6; border-radius: 50%; background: #e16b4c; }
.user-summary { display: flex; align-items: center; gap: 10px; color: #18352d; text-decoration: none; }
.user-avatar { display: grid; width: 34px; height: 34px; place-items: center; border-radius: 50%; background: #dce8ba; font-size: 12px; font-weight: 800; }
.user-avatar[style*="background-image"] { background-position: center; background-size: cover; }
.user-summary > span:last-child { display: grid; gap: 3px; }
.user-summary strong { font-size: 11px; }
.user-summary small { color: #829187; font-size: 9px; }
.workspace-main { width: min(1240px, 100%); min-height: calc(100vh - 72px); margin: 0 auto; padding: 30px 34px 48px; }
.compact-workspace .workspace-main { padding-top: 18px; }
.compact-workspace .surface-card { border-radius: 0; }
.compact-workspace .employee-card, .compact-workspace .announcement-card, .compact-workspace .resource-card { padding: 13px; }
.workspace-main > main { min-height: calc(100vh - 150px); }
.backend-alert { margin-bottom: 18px; font-size: 11px; }
.page-heading { display: flex; align-items: end; justify-content: space-between; gap: 20px; margin: 6px 0 25px; }
.page-heading .eyebrow { margin: 0 0 9px; color: #71897b; font: 10px "DM Mono", monospace; letter-spacing: 1.5px; }
.page-heading h1 { margin: 0; color: #18352d; font-size: clamp(28px, 3vw, 38px); line-height: 1.1; letter-spacing: -1.8px; }
.page-heading p { max-width: 620px; margin: 9px 0 0; color: #718178; font-size: 12px; line-height: 1.7; }
.primary-action, .secondary-action {
  display: inline-flex;
  min-height: 40px;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border: 1px solid #18352d;
  padding: 0 14px;
  background: #18352d;
  color: #f5f6ee;
  cursor: pointer;
  text-decoration: none;
  font: 700 11px "Manrope", sans-serif;
}
.secondary-action { border-color: #d1dbcd; background: #fff; color: #18352d; }
.primary-action:hover { background: #285346; }
.secondary-action:hover { border-color: #93a98e; }
.toolbar { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; margin-bottom: 18px; }
.field-control {
  min-height: 40px;
  border: 1px solid #d5ded2;
  border-radius: 0;
  padding: 0 12px;
  background: #fff;
  color: #18352d;
  font: 11px "Manrope", sans-serif;
}
.toolbar .field-control { min-width: 210px; }
.surface-card { border: 1px solid #dce4d8; background: #fff; }
.empty-state { padding: 42px 24px; color: #718178; text-align: center; }
.empty-state .v-icon { color: #91a398; }
.empty-state h2 { margin: 12px 0 5px; color: #18352d; font-size: 17px; }
.empty-state p { margin: 0; font-size: 11px; }
.data-table { width: 100%; border-collapse: collapse; text-align: left; }
.data-table th { padding: 12px 15px; color: #829187; font: 9px "DM Mono", monospace; letter-spacing: 1px; }
.data-table td { padding: 13px 15px; border-top: 1px solid #edf0e9; color: #52645a; font-size: 11px; }
@media (max-width: 900px) {
  .sidebar { width: 190px; padding-right: 10px; padding-left: 10px; }
  .workspace-column { margin-left: 190px; }
  .topbar { padding: 0 22px; }
  .workspace-main { padding: 25px 22px 38px; }
}
@media (max-width: 680px) {
  .sidebar { position: sticky; inset: 0 0 auto; width: 100%; height: auto; padding: 12px 14px 8px; }
  .sidebar .brand { padding: 0 4px 10px; }
  .nav-label, .sidebar-bottom { display: none; }
  .side-nav { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 3px; }
  .side-nav a { min-height: 34px; gap: 7px; padding: 0 8px; font-size: 9px; }
  .side-nav a.active { box-shadow: inset 2px 0 #d4ec66; }
  .side-nav a .v-icon { display: none; }
  .workspace-column { margin-left: 0; }
  .topbar { position: relative; height: auto; min-height: 64px; flex-wrap: wrap; gap: 10px; padding: 10px 18px; }
  .topbar > .global-search { order: 2; }
  .topbar-actions { margin-left: auto; }
  .user-summary small { display: none; }
  .workspace-main { padding: 23px 17px 32px; }
  .page-heading { align-items: flex-start; flex-direction: column; }
  .toolbar .field-control { flex: 1 1 100%; width: 100%; }
  .data-table { min-width: 640px; }
  .table-scroll { overflow-x: auto; }
}
</style>
