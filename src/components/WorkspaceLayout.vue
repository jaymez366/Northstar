<script setup lang="ts">
  import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import GlobalSearch from '@/components/GlobalSearch.vue'
  import ThemeSwitcher from '@/components/ThemeSwitcher.vue'
  import { useAuthStore } from '@/stores/auth'
  import { useWorkspaceStore } from '@/stores/workspace'

  const auth = useAuthStore()
  const workspace = useWorkspaceStore()
  const router = useRouter()
  const route = useRoute()
  const mobileMenuOpen = ref(false)
  const employeeProfileMenuOpen = ref(false)
  const mobileMenuToggle = ref<HTMLButtonElement | null>(null)
  const mobileMenuClose = ref<HTMLButtonElement | null>(null)
  let previousBodyOverflow = ''

  const employeeDisplayName = computed(() => {
    const fullName = [auth.profile.firstName, auth.profile.lastName].filter(Boolean).join(' ').trim()
    return fullName || auth.userFirstName || 'Northstar member'
  })
  const employeeInitials = computed(() => {
    const nameParts = employeeDisplayName.value.split(/\s+/).filter(Boolean)
    return nameParts.length > 1
      ? `${nameParts[0][0]}${nameParts[nameParts.length - 1][0]}`.toUpperCase()
      : (nameParts[0]?.slice(0, 2) || 'NS').toUpperCase()
  })

  const primaryLinks = [
    { title: 'Overview', to: '/overview', icon: 'mdi-view-dashboard-outline' },
    { title: 'Messages', to: '/messages', icon: 'mdi-message-text-outline' },
    { title: 'Expert support', to: '/support-inquiries', icon: 'mdi-lifebuoy' },
    { title: 'Announcements', to: '/announcements', icon: 'mdi-bullhorn-outline' },
    { title: 'Employees', to: '/employees', icon: 'mdi-account-group-outline' },
    { title: 'Departments', to: '/departments', icon: 'mdi-domain' },
    { title: 'Events', to: '/events', icon: 'mdi-calendar-month-outline' },
    { title: 'Resources', to: '/resources', icon: 'mdi-folder-outline' },
    { title: 'Disaster management', to: '/disaster-management', icon: 'mdi-shield-alert-outline' },
  ]

  async function logout () {
    closeMobileNavigation()
    if (await auth.logout()) {
      workspace.clearWorkspace()
      await router.replace('/login')
    }
  }

  function closeMobileNavigation () {
    mobileMenuOpen.value = false
  }

  function handleMobileMenuKeydown (event: KeyboardEvent) {
    if (event.key === 'Escape') {
      closeMobileNavigation()
      nextTick(() => mobileMenuToggle.value?.focus())
    }
  }

  function handleViewportResize () {
    if (window.matchMedia('(min-width: 681px)').matches) closeMobileNavigation()
  }

  watch(mobileMenuOpen, async isOpen => {
    if (isOpen) {
      previousBodyOverflow = document.body.style.overflow
      document.body.style.overflow = 'hidden'
      window.addEventListener('keydown', handleMobileMenuKeydown)
      await nextTick()
      mobileMenuClose.value?.focus()
      return
    }

    document.body.style.overflow = previousBodyOverflow
    window.removeEventListener('keydown', handleMobileMenuKeydown)
  })

  watch(() => route.fullPath, closeMobileNavigation)

  function openMessageToast () {
    const conversationId = workspace.messageToast?.conversationId
    const notificationId = workspace.messageToast?.notificationId
    if (notificationId) void workspace.markNotificationRead(notificationId)
    workspace.dismissMessageToast()
    void router.push(conversationId ? { path: '/messages', query: { conversation: conversationId } } : '/messages')
  }

  watch(() => auth.isAuthenticated, authenticated => {
    if (!authenticated) workspace.clearWorkspace()
  })

  onMounted(() => {
    window.addEventListener('resize', handleViewportResize)
    void workspace.load()
    if (auth.canAccessEmployeeWorkspace) {
      workspace.subscribeToMessages()
    }
  })

  onUnmounted(() => workspace.unsubscribeFromMessages())
  onUnmounted(() => {
    document.body.style.overflow = previousBodyOverflow
    window.removeEventListener('keydown', handleMobileMenuKeydown)
    window.removeEventListener('resize', handleViewportResize)
  })
</script>

<template>
  <div class="workspace-shell">
    <button
      v-if="mobileMenuOpen"
      aria-label="Close navigation menu"
      class="mobile-menu-backdrop"
      type="button"
      @click="closeMobileNavigation"
    />

    <aside id="workspace-navigation" class="sidebar" :class="{ 'mobile-menu-open': mobileMenuOpen }">
      <div class="sidebar-heading">
        <router-link aria-label="Northstar home" class="brand" to="/" @click="closeMobileNavigation">
          <span class="brand-mark"><span /><span /><span /></span>
          <span>northstar<span class="brand-dot">.</span></span>
        </router-link>
        <button
          ref="mobileMenuClose"
          aria-label="Close navigation menu"
          class="mobile-menu-close"
          type="button"
          @click="closeMobileNavigation"
        >
          <v-icon icon="mdi-close" size="22" />
        </button>
      </div>

      <p class="nav-label">WORKSPACE</p>

      <nav aria-label="Workspace navigation" class="side-nav">
        <router-link
          v-for="link in primaryLinks"
          :key="link.to"
          active-class="active"
          :to="link.to"
          @click="closeMobileNavigation"
        >
          <v-icon :icon="link.icon" size="19" />
          <span>{{ link.title }}</span>
        </router-link>

        <router-link active-class="active" to="/notifications" @click="closeMobileNavigation">
          <v-icon icon="mdi-bell-outline" size="19" />
          <span>Notifications</span>
          <span v-if="workspace.unreadNotifications" class="unread-count">{{ workspace.unreadNotifications }}</span>
        </router-link>
        <div class="sidebar-bottom">
          <router-link active-class="active" to="/profile" @click="closeMobileNavigation">
            <v-icon icon="mdi-account-circle-outline" size="19" />
            <span>Profile</span>
          </router-link>

          <router-link active-class="active" to="/settings" @click="closeMobileNavigation">
            <v-icon icon="mdi-cog-outline" size="19" />
            <span>Settings</span>
          </router-link>

        <router-link v-if="!auth.isAdmin" active-class="active" to="/rejection-history" @click="closeMobileNavigation">
          <v-icon icon="mdi-history" size="19" />
          <span>Registration history</span>
        </router-link>

          <router-link v-if="auth.isAdmin" active-class="active" to="/admin" @click="closeMobileNavigation">
            <v-icon icon="mdi-shield-account-outline" size="19" />
            <span>Admin dashboard</span>
          </router-link>

          <button class="logout-button" type="button" @click="logout">
            <v-icon icon="mdi-logout" size="19" />
            <span>Sign out</span>
          </button>
        </div>
      </nav>
    </aside>

    <div class="workspace-column">
      <header class="topbar">
        <button
          ref="mobileMenuToggle"
          :aria-expanded="mobileMenuOpen"
          aria-controls="workspace-navigation"
          :aria-label="mobileMenuOpen ? 'Close navigation menu' : 'Open navigation menu'"
          class="mobile-menu-toggle"
          type="button"
          @click="mobileMenuOpen = !mobileMenuOpen"
        >
          <v-icon :icon="mobileMenuOpen ? 'mdi-close' : 'mdi-menu'" size="23" />
        </button>
        <GlobalSearch />

        <div class="topbar-actions">
          <ThemeSwitcher />
          <router-link aria-label="Notifications" class="notification-button" to="/notifications">
            <v-icon icon="mdi-bell-outline" size="21" />
            <span v-if="workspace.unreadNotifications" class="notification-dot" />
          </router-link>

          <v-menu v-model="employeeProfileMenuOpen" location="bottom end" :close-on-content-click="true">
            <template #activator="{ props }">
              <button
                v-bind="props"
                class="user-summary"
                type="button"
                aria-label="Open employee profile menu"
                aria-haspopup="menu"
                :aria-expanded="employeeProfileMenuOpen"
              >
                <span
                  class="user-avatar"
                  :style="auth.profile.photoUrl ? { backgroundImage: `url(${auth.profile.photoUrl})` } : undefined"
                  aria-hidden="true"
                >{{ !auth.profile.photoUrl && employeeInitials }}</span>
                <span class="user-summary-copy">
                  <strong>{{ employeeDisplayName }}</strong>
                  <small>{{ auth.profile.jobTitle || 'Northstar member' }}</small>
                </span>
                <v-icon class="user-menu-chevron" icon="mdi-chevron-down" size="17" aria-hidden="true" />
              </button>
            </template>

            <v-list class="employee-profile-menu" density="compact" role="menu">
              <v-list-item
                prepend-icon="mdi-account-circle-outline"
                title="Profile"
                to="/profile"
                role="menuitem"
              />
              <v-list-item
                prepend-icon="mdi-cog-outline"
                title="Settings"
                to="/settings"
                role="menuitem"
              />
              <v-divider class="my-1" />
              <v-list-item
                prepend-icon="mdi-logout"
                title="Sign Out"
                role="menuitem"
                @click="logout"
              />
            </v-list>
          </v-menu>
        </div>
      </header>

      <main class="workspace-main">
        <v-progress-linear
          v-if="workspace.loading"
          aria-label="Loading workspace data"
          color="primary"
          indeterminate
        />

        <v-alert
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

        <slot />
      </main>
    </div>
    <v-snackbar
      :model-value="Boolean(workspace.messageToast)"
      location="bottom right"
      :timeout="-1"
      @update:model-value="visible => { if (!visible) workspace.dismissMessageToast() }"
    >
      <button class="message-toast" type="button" @click="openMessageToast">
        <strong>{{ workspace.messageToast?.title }}</strong>
        <span>{{ workspace.messageToast?.preview }}</span>
      </button>
      <template #actions>
        <v-btn color="secondary" variant="text" @click="openMessageToast">Open</v-btn>
        <v-btn icon="mdi-close" variant="text" aria-label="Dismiss message notification" @click="workspace.dismissMessageToast" />
      </template>
    </v-snackbar>
  </div>
</template>

<style>
@import url("https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Manrope:wght@400;500;600;700;800&display=swap");

:root {
  font-family: "Manrope", sans-serif;
  color: var(--ns-text-10231d, #10231d);
  background: var(--ns-bg-f3f5ef, #f3f5ef);
  font-synthesis: none;
}
* { box-sizing: border-box; }
body { min-width: 320px; margin: 0; background: var(--ns-bg-f3f5ef, #f3f5ef); }
.v-application, .v-main { background: var(--ns-bg-f3f5ef, #f3f5ef) !important; color: var(--ns-text-10231d, #10231d); }
.workspace-shell { min-height: 100vh; }
.sidebar {
  position: fixed;
  z-index: 10;
  inset: 0 auto 0 0;
  display: flex;
  width: 232px;
  height: 100vh;
  height: 100dvh;
  flex-direction: column;
  overflow: hidden;
  padding: 26px 16px 18px;
  background: var(--ns-bg-102d26, #102d26);
  color: var(--ns-text-f5f6ee, #f5f6ee);
}
.brand {
  display: flex;
  flex-shrink: 0;
  align-items: center;
  gap: 10px;
  padding: 0 10px;
  color: inherit;
  text-decoration: none;
  font-size: 20px;
  font-weight: 800;
  letter-spacing: -1px;
}
.sidebar-heading { display: flex; flex-shrink: 0; align-items: center; justify-content: space-between; }
.mobile-menu-toggle, .mobile-menu-close { display: none; }
.mobile-menu-backdrop { display: none; }
.brand-mark { display: flex; align-items: end; gap: 2px; height: 20px; }
.brand-mark span { display: block; width: 5px; background: var(--ns-bg-d4ec66, #d4ec66); }
.brand-mark span:nth-child(1) { height: 11px; }
.brand-mark span:nth-child(2) { height: 17px; }
.brand-mark span:nth-child(3) { height: 14px; }
.brand-dot { color: var(--ns-text-d4ec66, #d4ec66); }
.nav-label {
  flex-shrink: 0;
  margin: 48px 10px 12px;
  color: var(--ns-text-82998b, #82998b);
  font: 9px "DM Mono", monospace;
  letter-spacing: 1.5px;
}
.side-nav {
  display: flex;
  min-height: 0;
  flex: 1 1 auto;
  flex-direction: column;
  gap: 4px;
  overflow-y: auto;
  overscroll-behavior: contain;
  scrollbar-width: thin;
  scrollbar-color: var(--ns-scrollbar-thumb) transparent;
  -webkit-overflow-scrolling: touch;
}
.sidebar-bottom { display: grid; gap: 4px; }
.side-nav a, .sidebar-bottom a, .logout-button {
  display: flex;
  min-height: 41px;
  align-items: center;
  gap: 12px;
  border: 0;
  padding: 0 11px;
  background: transparent;
  color: var(--ns-text-bac9bd, #bac9bd);
  cursor: pointer;
  text-align: left;
  text-decoration: none;
  font: 500 11px "Manrope", sans-serif;
}
.side-nav a:hover, .sidebar-bottom a:hover, .logout-button:hover,
.side-nav a.active, .sidebar-bottom a.active {
  background: var(--ns-bg-1d4035, #1d4035);
  color: var(--ns-text-d4ec66, #d4ec66);
}
.side-nav a.active { box-shadow: inset 2px 0 var(--ns-shadow-d4ec66, #d4ec66); }
.unread-count { margin-left: auto; color: var(--ns-text-d4ec66, #d4ec66); font-size: 10px; }
.sidebar-bottom { margin-top: auto; padding-top: 16px; border-top: 1px solid var(--ns-border-ffffff1c, #ffffff1c); }
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
  border-bottom: 1px solid var(--ns-border-dce4d8, #dce4d8);
  background: var(--ns-bg-f9faf6ed, #f9faf6ed);
  backdrop-filter: blur(12px);
}
.topbar-actions { display: flex; align-items: center; gap: 22px; }
.notification-button { position: relative; color: var(--ns-text-526c5c, #526c5c); }
.notification-dot { position: absolute; top: 1px; right: 0; width: 7px; height: 7px; border: 1px solid var(--ns-border-f9faf6, #f9faf6); border-radius: 50%; background: var(--ns-bg-e16b4c, #e16b4c); }
.user-summary { display: flex; min-width: 0; align-items: center; gap: 10px; border: 0; padding: 4px 0 4px 4px; background: transparent; color: var(--ns-text-18352d, #18352d); cursor: pointer; text-align: left; }
.user-summary:focus-visible { border-radius: 8px; outline: 2px solid var(--ns-primary); outline-offset: 3px; }
.user-avatar { display: grid; width: 34px; height: 34px; place-items: center; border-radius: 50%; background: var(--ns-bg-dce8ba, #dce8ba); font-size: 12px; font-weight: 800; }
.user-avatar[style*="background-image"] { background-position: center; background-size: cover; }
.user-summary-copy { display: grid; min-width: 0; gap: 3px; }
.user-summary strong { font-size: 11px; }
.user-summary small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.user-menu-chevron { flex: 0 0 auto; color: var(--ns-text-secondary); }
.employee-profile-menu { min-width: 190px; max-width: min(280px, calc(100vw - 24px)); background: var(--ns-surface); color: var(--ns-text-primary); }
.employee-profile-menu .v-list-item { color: var(--ns-text-primary); }
.employee-profile-menu .v-list-item:hover { background: var(--ns-surface-hover); }
.workspace-main { width: min(1240px, 100%); min-height: calc(100vh - 72px); margin: 0 auto; padding: 30px 34px 48px; }
.compact-workspace .workspace-main { padding-top: 18px; }
.compact-workspace .surface-card { border-radius: 0; }
.compact-workspace .employee-card, .compact-workspace .announcement-card, .compact-workspace .resource-card { padding: 13px; }
.workspace-main > main { min-height: calc(100vh - 150px); }
.backend-alert { margin-bottom: 18px; font-size: 11px; }
.message-toast { display: grid; max-width: min(58vw, 420px); gap: 4px; border: 0; background: transparent; color: inherit; cursor: pointer; text-align: left; }
.message-toast strong { font-size: 12px; }
.message-toast span { overflow: hidden; font-size: 11px; text-overflow: ellipsis; white-space: nowrap; }
.page-heading { display: flex; align-items: end; justify-content: space-between; gap: 20px; margin: 6px 0 25px; }
.page-heading .eyebrow { margin: 0 0 9px; color: var(--ns-text-71897b, #71897b); font: 10px "DM Mono", monospace; letter-spacing: 1.5px; }
.page-heading h1 { margin: 0; color: var(--ns-text-18352d, #18352d); font-size: clamp(28px, 3vw, 38px); line-height: 1.1; letter-spacing: -1.8px; }
.page-heading p { max-width: 620px; margin: 9px 0 0; color: var(--ns-text-718178, #718178); font-size: 12px; line-height: 1.7; }
.primary-action, .secondary-action {
  display: inline-flex;
  min-height: 40px;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border: 1px solid var(--ns-border-18352d, #18352d);
  padding: 0 14px;
  background: var(--ns-bg-18352d, #18352d);
  color: var(--ns-text-f5f6ee, #f5f6ee);
  cursor: pointer;
  text-decoration: none;
  font: 700 11px "Manrope", sans-serif;
}
.secondary-action { border-color: var(--ns-border-d1dbcd, #d1dbcd); background: var(--ns-bg-fff, #fff); color: var(--ns-text-18352d, #18352d); }
.primary-action:hover { background: var(--ns-primary-hover); border-color: var(--ns-primary-hover); }
.primary-action:focus-visible, .secondary-action:focus-visible { outline: 3px solid var(--ns-blue-border); outline-offset: 2px; }
.secondary-action:hover { border-color: var(--ns-border-93a98e, #93a98e); }
.toolbar { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; margin-bottom: 18px; }
.field-control {
  min-height: 40px;
  border: 1px solid var(--ns-border-d5ded2, #d5ded2);
  border-radius: 0;
  padding: 0 12px;
  background: var(--ns-bg-fff, #fff);
  color: var(--ns-text-18352d, #18352d);
  font: 11px "Manrope", sans-serif;
}
.toolbar .field-control { min-width: 210px; }
.surface-card { border: 1px solid var(--ns-border-dce4d8, #dce4d8); background: var(--ns-bg-fff, #fff); }
.empty-state { padding: 42px 24px; color: var(--ns-text-718178, #718178); text-align: center; }
.empty-state .v-icon { color: var(--ns-text-91a398, #91a398); }
.empty-state h2 { margin: 12px 0 5px; color: var(--ns-text-18352d, #18352d); font-size: 17px; }
.empty-state p { margin: 0; font-size: 11px; }
.data-table { width: 100%; border-collapse: collapse; text-align: left; }
.data-table th { padding: 12px 15px; color: var(--ns-text-829187, #829187); font: 9px "DM Mono", monospace; letter-spacing: 1px; }
.data-table td { padding: 13px 15px; border-top: 1px solid var(--ns-border-edf0e9, #edf0e9); color: var(--ns-text-52645a, #52645a); font-size: 11px; }
@media (max-width: 900px) {
  .sidebar { width: 190px; padding-right: 10px; padding-left: 10px; }
  .workspace-column { margin-left: 190px; }
  .topbar { padding: 0 22px; }
  .workspace-main { padding: 25px 22px 38px; }
}
@media (max-width: 680px) {
  .sidebar {
    position: fixed;
    z-index: 30;
    inset: 0 auto 0 0;
    width: min(320px, 88vw);
    height: 100vh;
    height: 100dvh;
    max-height: none;
    padding: 18px 16px 14px;
    box-shadow: 18px 0 48px rgb(7 15 28 / 24%);
    transform: translateX(-105%);
    visibility: hidden;
    pointer-events: none;
    transition: transform 180ms ease, visibility 0s linear 180ms;
  }
  .sidebar.mobile-menu-open {
    transform: translateX(0);
    visibility: visible;
    pointer-events: auto;
    transition: transform 180ms ease;
  }
  .sidebar-heading { min-height: 44px; gap: 12px; }
  .sidebar .brand { padding: 0 4px; }
  .mobile-menu-close {
    display: grid;
    width: 42px;
    height: 42px;
    flex: 0 0 42px;
    place-items: center;
    border: 1px solid var(--ns-border);
    border-radius: 9px;
    background: var(--ns-surface-raised);
    color: var(--ns-text-primary);
    cursor: pointer;
  }
  .mobile-menu-close:focus-visible,
  .mobile-menu-toggle:focus-visible { outline: 2px solid var(--ns-primary); outline-offset: 2px; }
  .mobile-menu-backdrop {
    position: fixed;
    z-index: 29;
    inset: 0;
    display: block;
    border: 0;
    background: rgb(8 15 27 / 48%);
    cursor: default;
  }
  .nav-label { display: block; margin: 22px 10px 10px; }
  .side-nav { display: flex; max-height: none; flex: 1 1 auto; gap: 5px; overflow-y: auto; }
  .sidebar-bottom { display: grid; margin-top: auto; }
  .side-nav a, .sidebar-bottom a, .logout-button { min-height: 48px; gap: 12px; padding: 0 12px; font-size: 12px; }
  .side-nav a.active { box-shadow: inset 3px 0 var(--ns-primary); }
  .side-nav a .v-icon { display: inline-flex; }
  .workspace-column { margin-left: 0; }
  .topbar { position: sticky; height: auto; min-height: 64px; flex-wrap: wrap; gap: 10px; padding: 10px 14px; }
  .mobile-menu-toggle {
    display: grid;
    width: 42px;
    height: 42px;
    flex: 0 0 42px;
    place-items: center;
    border: 1px solid var(--ns-border);
    border-radius: 9px;
    background: var(--ns-surface);
    color: var(--ns-text-primary);
    cursor: pointer;
  }
  .topbar > .global-search { order: 2; }
  .topbar-actions { gap: 12px; margin-left: auto; }
  .user-summary { max-width: min(42vw, 210px); gap: 7px; }
  .user-summary-copy { overflow: hidden; }
  .user-summary strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .user-summary small { display: none; }
  .workspace-main { padding: 23px 17px 32px; }
  .page-heading { align-items: flex-start; flex-direction: column; }
  .toolbar .field-control { flex: 1 1 100%; width: 100%; }
  .data-table { min-width: 640px; }
  .table-scroll { overflow-x: auto; }
}
</style>
