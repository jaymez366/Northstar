<script setup lang="ts">
  import { computed, onMounted, onUnmounted, ref } from 'vue'
  import { useAuthStore } from '@/stores/auth'
  import { useWorkspaceStore } from '@/stores/workspace'

  const auth = useAuthStore()
  const workspace = useWorkspaceStore()
  const currentTime = ref(new Date())
  let clockInterval: ReturnType<typeof setInterval>

  const greeting = computed(() => {
    const hour = currentTime.value.getHours()

    if (hour >= 5 && hour < 12) {
      return 'Good Morning,'
    }

    if (hour >= 12 && hour < 17) {
      return 'Good Afternoon,'
    }

    return 'Good Evening,'
  })

  const formattedDate = computed(() => new Intl.DateTimeFormat(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  }).format(currentTime.value))
  const recentAnnouncements = computed(() => workspace.announcements.slice(0, 3))
  const recentConversations = computed(() => workspace.conversations.slice(0, 3))
  const upcomingEvents = computed(() => workspace.events.slice(0, 3))

  onMounted(() => {
    clockInterval = setInterval(() => {
      currentTime.value = new Date()
    }, 60_000)
  })

  onUnmounted(() => clearInterval(clockInterval))
</script>

<template>
  <main class="overview-page">
    <div class="overview-content">
      <section class="welcome-panel">
        <div>
          <p class="eyebrow">YOUR NORTHSTAR WORKSPACE</p>
          <h1>{{ greeting }}<br><em>{{ auth.profile.firstName || auth.userFirstName }}.</em></h1>

          <p class="welcome-copy">
            Here’s what’s happening across your organization today.
          </p>
        </div>

        <div class="date-card">
          <span class="date-icon"><v-icon icon="mdi-calendar-blank-outline" size="19" /></span>
          <span><small>TODAY</small><strong>{{ formattedDate }}</strong></span>
        </div>
      </section>

      <section aria-label="Quick actions" class="quick-actions">
        <router-link class="primary-action" to="/employee-communication"><v-icon icon="mdi-plus" size="17" /> New announcement</router-link>
        <router-link class="secondary-action" to="/messages"><v-icon icon="mdi-message-outline" size="17" /> Open messages</router-link>
        <router-link class="secondary-action" to="/employees"><v-icon icon="mdi-account-search-outline" size="17" /> Find a colleague</router-link>
      </section>

      <section aria-label="Workspace summary" class="summary-grid">
        <article class="summary-card">
          <div class="card-topline">
            <span class="card-icon lime"><v-icon icon="mdi-account-group-outline" size="20" /></span>
            <span class="status-label"><span /> ALL SYSTEMS READY</span>
          </div>

          <p class="metric">{{ workspace.employees.length }}</p>
          <h2>People in your organization</h2>
          <p class="card-detail">Across {{ workspace.departments.length }} departments</p>
        </article>

        <article class="summary-card dark-card">
          <div class="card-topline">
            <span class="card-icon coral"><v-icon icon="mdi-message-text-outline" size="20" /></span>
            <span class="status-label">THIS WEEK</span>
          </div>

          <p class="metric">{{ workspace.unreadNotifications }}</p>
          <h2>Unread notifications</h2>
          <p class="card-detail">Updates that may need your attention</p>
        </article>

        <article class="summary-card">
          <div class="card-topline">
            <span class="card-icon peach"><v-icon icon="mdi-shield-check-outline" size="20" /></span>
            <span class="status-label">RESPONSE STATUS</span>
          </div>

          <p class="metric">{{ workspace.conversations.filter(item => item.unread > 0).length }}</p>
          <h2>Unread conversations</h2>
          <p class="card-detail">Direct messages from your colleagues</p>
        </article>
      </section>

      <section class="overview-columns">
        <div class="overview-column">
          <section class="dashboard-section surface-card">
            <header class="dashboard-section-heading"><div><p class="eyebrow">LATEST UPDATES</p><h2>Recent announcements</h2></div><router-link to="/announcements">View all <v-icon icon="mdi-arrow-right" size="14" /></router-link></header>

            <article v-for="item in recentAnnouncements" :key="item.id" class="compact-item">
              <span class="compact-icon"><v-icon icon="mdi-bullhorn-outline" size="17" /></span>
              <span><strong>{{ item.title }}</strong><small>{{ item.author }} · {{ new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(item.createdAt)) }}</small></span>
              <span v-if="item.pinned" class="pinned-dot" title="Pinned"><v-icon icon="mdi-pin" size="14" /></span>
            </article>

            <div v-if="recentAnnouncements.length === 0" class="compact-empty">No announcements yet.</div>
          </section>

          <section class="dashboard-section surface-card">
            <header class="dashboard-section-heading"><div><p class="eyebrow">KEEP IN TOUCH</p><h2>Recent messages</h2></div><router-link to="/messages">Open inbox <v-icon icon="mdi-arrow-right" size="14" /></router-link></header>

            <router-link v-for="conversation in recentConversations" :key="conversation.id" class="compact-item message-item" :to="{ path: '/messages', query: { employee: conversation.employeeId } }">
              <span class="compact-avatar" :style="{ background: conversation.color }">{{ conversation.initials }}</span>
              <span><strong>{{ conversation.name }}</strong><small>{{ conversation.messages.at(-1)?.text }}</small></span>
              <span v-if="conversation.unread" class="message-unread">{{ conversation.unread }}</span>
            </router-link>
          </section>
        </div>

        <div class="overview-column">
          <section class="dashboard-section surface-card">
            <header class="dashboard-section-heading"><div><p class="eyebrow">SAVE THE DATE</p><h2>Upcoming events</h2></div><router-link to="/events">All events <v-icon icon="mdi-arrow-right" size="14" /></router-link></header>

            <router-link v-for="event in upcomingEvents" :key="event.id" class="event-preview" to="/events">
              <span class="event-preview-date"><small>{{ new Intl.DateTimeFormat(undefined, { month: 'short' }).format(new Date(event.startsAt)) }}</small><strong>{{ new Date(event.startsAt).getDate() }}</strong></span>
              <span><strong>{{ event.title }}</strong><small>{{ new Intl.DateTimeFormat(undefined, { weekday: 'short', hour: 'numeric', minute: '2-digit' }).format(new Date(event.startsAt)) }} · {{ event.location }}</small></span>
              <v-icon icon="mdi-chevron-right" size="18" />
            </router-link>
          </section>

          <router-link class="notification-summary surface-card" to="/notifications">
            <span class="notification-summary-icon"><v-icon icon="mdi-bell-outline" size="20" /></span>
            <span><small>NOTIFICATIONS</small><strong>{{ workspace.unreadNotifications }} unread updates</strong><small>Announcements, messages, and event reminders</small></span>
            <v-icon icon="mdi-arrow-top-right" size="18" />
          </router-link>

          <section class="feature-links">
            <router-link class="workspace-card communication-card" to="/employee-communication">
              <span class="workspace-icon"><v-icon icon="mdi-message-text-outline" size="22" /></span>
              <span class="workspace-copy"><small>EVERYDAY ALIGNMENT</small><strong>Employee communication</strong><span>Share clear updates with your people.</span></span>
              <v-icon class="workspace-arrow" icon="mdi-arrow-top-right" size="20" />
            </router-link>

            <router-link class="workspace-card response-card" to="/disaster-management">
              <span class="workspace-icon"><v-icon icon="mdi-shield-alert-outline" size="22" /></span>
              <span class="workspace-copy"><small>WHEN IT MATTERS MOST</small><strong>Disaster management</strong><span>Coordinate people and response actions.</span></span>
              <v-icon class="workspace-arrow" icon="mdi-arrow-top-right" size="20" />
            </router-link>
          </section>
        </div>
      </section>

      <footer class="overview-footer">
        <span>Internal clarity for external confidence.</span>

        <router-link to="/start-conversation">
          Need a hand? Talk to our team <v-icon icon="mdi-arrow-top-right" size="15" />
        </router-link>
      </footer>
    </div>
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
.overview-page { min-height: 100vh; }
.overview-header {
  height: 82px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  padding: 0 max(32px, calc((100vw - 1160px) / 2));
  background: #102d26;
  color: #f5f6ee;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
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
.workspace-nav { display: flex; align-items: center; gap: 30px; }
.workspace-nav a {
  color: #bac9bd;
  text-decoration: none;
  font-size: 12px;
  font-weight: 600;
}
.workspace-nav a:hover,
.workspace-nav a.active { color: #d4ec66; }
.account-link {
  display: flex;
  align-items: center;
  gap: 9px;
  border: 0;
  padding: 0;
  background: transparent;
  color: #f5f6ee;
  cursor: pointer;
  text-decoration: none;
  font-size: 12px;
  font-weight: 700;
  font-family: inherit;
}
.account-avatar {
  display: grid;
  width: 32px;
  height: 32px;
  place-items: center;
  border-radius: 50%;
  background: #d4ec66;
  color: #102d26;
}
.overview-content { width: min(1160px, calc(100% - 64px)); margin: 0 auto; }
.quick-actions { display: flex; flex-wrap: wrap; gap: 8px; margin: -23px 0 21px; }
.welcome-panel {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 24px;
  padding: 65px 0 48px;
}
.welcome-panel > div:first-child { flex: 1; }
.date-card { flex: none; }
.eyebrow,
.status-label,
.date-card small,
.workspace-copy small {
  color: #71897b;
  font: 10px "DM Mono", monospace;
  letter-spacing: 1.4px;
}
.welcome-panel h1 {
  margin: 17px 0 13px;
  color: #18352d;
  font-size: clamp(40px, 5vw, 58px);
  line-height: .98;
  letter-spacing: -4px;
}
.welcome-panel h1 em { color: #e16b4c; font-style: normal; }
.welcome-copy { margin: 0; color: #718178; font-size: 14px; }
.date-card {
  display: flex;
  align-items: center;
  gap: 13px;
  margin-bottom: 7px;
  padding: 16px 20px;
  border: 1px solid #dce4d8;
  background: #fff;
}
.date-icon { color: #e16b4c; }
.date-card span:last-child { display: grid; gap: 5px; }
.date-card small { font-size: 9px; }
.date-card strong { color: #18352d; font-size: 12px; }
.summary-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
.summary-card { min-height: 200px; padding: 22px 24px; background: #fff; }
.dark-card { background: #18352d; color: #f3f5ef; }
.card-topline { display: flex; align-items: center; justify-content: space-between; }
.card-icon {
  display: grid;
  width: 38px;
  height: 38px;
  place-items: center;
  color: #18352d;
}
.card-icon.lime { background: #eaf3bd; }
.card-icon.coral { background: #f5d4c9; }
.card-icon.peach { background: #f8e4d8; }
.status-label { font-size: 8px; letter-spacing: 1px; }
.dark-card .status-label { color: #bdcbbf; }
.status-label span {
  display: inline-block;
  width: 6px;
  height: 6px;
  margin-right: 5px;
  border-radius: 50%;
  background: #79bb83;
}
.metric { margin: 19px 0 1px; color: #18352d; font-size: 31px; font-weight: 800; letter-spacing: -1.5px; }
.dark-card .metric { color: #d4ec66; }
.summary-card h2 { margin: 0; font-size: 12px; font-weight: 700; }
.card-detail { margin: 7px 0 0; color: #829187; font-size: 10px; }
.dark-card .card-detail { color: #aabcae; }
.overview-columns { display: grid; grid-template-columns: 1.1fr .9fr; align-items: start; gap: 15px; padding-top: 28px; }
.overview-column { display: grid; gap: 13px; }
.dashboard-section { padding: 16px; }
.dashboard-section-heading { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 8px; }
.dashboard-section-heading .eyebrow { margin: 0 0 5px; font-size: 8px; }
.dashboard-section-heading h2 { margin: 0; color: #18352d; font-size: 13px; }
.dashboard-section-heading > a { display: flex; align-items: center; gap: 4px; color: #60796a; text-decoration: none; font-size: 9px; white-space: nowrap; }
.compact-item { display: flex; min-width: 0; align-items: center; gap: 10px; padding: 11px 0; border-top: 1px solid #edf0e9; color: inherit; text-decoration: none; }
.compact-icon, .compact-avatar { display: grid; flex: 0 0 32px; width: 32px; height: 32px; place-items: center; background: #eef2e8; color: #687f6e; }
.compact-avatar { border-radius: 50%; color: #18352d; font-size: 8px; font-weight: 800; }
.compact-item > span:nth-child(2) { display: grid; min-width: 0; flex: 1; gap: 4px; }
.compact-item strong { overflow: hidden; color: #40564a; text-overflow: ellipsis; font-size: 9px; white-space: nowrap; }
.compact-item small { overflow: hidden; color: #89968d; text-overflow: ellipsis; font-size: 8px; white-space: nowrap; }
.pinned-dot { color: #809268; }
.message-item:hover strong { color: #bf593d; }
.message-unread { display: grid; width: 17px; height: 17px; place-items: center; border-radius: 50%; background: #d4ec66; color: #18352d; font-size: 8px; }
.compact-empty { padding: 18px 0; color: #829187; font-size: 10px; }
.event-preview { display: flex; align-items: center; gap: 10px; padding: 11px 0; border-top: 1px solid #edf0e9; color: inherit; text-decoration: none; }
.event-preview-date { display: grid; flex: 0 0 35px; height: 42px; align-content: center; justify-items: center; gap: 2px; background: #eaf3bd; color: #526738; }
.event-preview-date small { font: 7px "DM Mono", monospace; text-transform: uppercase; }
.event-preview-date strong { font-size: 14px; line-height: 1; }
.event-preview > span:nth-child(2) { display: grid; min-width: 0; flex: 1; gap: 4px; }
.event-preview > span:nth-child(2) strong { overflow: hidden; color: #40564a; text-overflow: ellipsis; font-size: 9px; white-space: nowrap; }
.event-preview > span:nth-child(2) small { overflow: hidden; color: #89968d; text-overflow: ellipsis; font-size: 8px; white-space: nowrap; }
.event-preview > .v-icon { color: #8a9a8f; }
.notification-summary { display: flex; align-items: center; gap: 12px; padding: 15px; color: inherit; text-decoration: none; }
.notification-summary-icon { display: grid; flex: 0 0 38px; width: 38px; height: 38px; place-items: center; background: #f5d4c9; color: #9e533f; }
.notification-summary > span:nth-child(2) { display: grid; flex: 1; gap: 4px; }
.notification-summary > span:nth-child(2) small { color: #829187; font-size: 8px; }
.notification-summary > span:nth-child(2) strong { color: #18352d; font-size: 10px; }
.notification-summary > .v-icon { color: #829187; }
.feature-links { display: grid; gap: 8px; }
.feature-links .workspace-card { min-height: auto; padding: 14px; }
.feature-links .workspace-copy { gap: 5px; }
.feature-links .workspace-copy strong { font-size: 11px; }
.feature-links .workspace-copy > span { font-size: 9px; }
.workspace-section { padding: 57px 0 64px; }
.section-heading { display: flex; align-items: end; justify-content: space-between; gap: 20px; margin-bottom: 20px; }
.section-heading .eyebrow { margin: 0 0 10px; }
.section-heading h2 { margin: 0; color: #18352d; font-size: 24px; letter-spacing: -1px; }
.section-heading > span { color: #829187; font-size: 11px; }
.workspace-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; }
.workspace-card {
  display: flex;
  align-items: flex-start;
  gap: 16px;
  min-height: 148px;
  padding: 23px;
  border: 1px solid #dce4d8;
  color: #18352d;
  text-decoration: none;
  transition: border-color .18s, transform .18s;
}
.workspace-card:hover { transform: translateY(-2px); border-color: #9caf91; }
.communication-card { background: #fff; }
.response-card { background: #e9efe3; }
.workspace-icon {
  display: grid;
  flex: 0 0 42px;
  width: 42px;
  height: 42px;
  place-items: center;
  background: #eaf3bd;
  color: #526738;
}
.response-card .workspace-icon { background: #f5d4c9; color: #a34c39; }
.workspace-copy { display: grid; gap: 8px; }
.workspace-copy small { font-size: 8px; }
.workspace-copy strong { font-size: 15px; }
.workspace-copy > span { max-width: 330px; color: #718178; font-size: 11px; line-height: 1.6; }
.workspace-arrow { margin-left: auto; color: #789082; }
.overview-footer {
  display: flex;
  justify-content: space-between;
  gap: 20px;
  padding: 20px 0 28px;
  border-top: 1px solid #dce4d8;
  color: #829187;
  font-size: 10px;
}
.overview-footer a { display: flex; align-items: center; gap: 6px; color: #526c5c; text-decoration: none; }
.overview-footer a:hover { color: #e16b4c; }
@media (max-width: 760px) {
  .overview-content { width: min(100% - 40px, 560px); }
  .welcome-panel { align-items: flex-start; flex-direction: column; padding: 48px 0 32px; }
  .welcome-panel h1 { font-size: clamp(38px, 8vw, 48px); letter-spacing: -2.5px; }
  .date-card { margin: 0; }
  .summary-grid { grid-template-columns: 1fr; gap: 10px; }
  .summary-card { min-height: 178px; }
  .overview-columns { grid-template-columns: 1fr; padding-top: 18px; }
  .workspace-card { padding: 18px; }
  .overview-footer { flex-direction: column; }
}
@media (max-width: 520px) {
  .overview-content { width: 100%; }
  .welcome-panel, .summary-grid, .quick-actions, .overview-columns, .overview-footer { margin-right: 0; margin-left: 0; padding-right: 15px; padding-left: 15px; }
  .summary-grid { grid-template-columns: 1fr; }
  .quick-actions > * { flex: 1 1 100%; }
}
</style>
