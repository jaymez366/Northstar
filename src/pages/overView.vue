<script setup lang="ts">
  import { computed, onMounted, onUnmounted, ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const router = useRouter()
  const currentTime = ref(new Date())
  let clockInterval: ReturnType<typeof setInterval>

  function logout () {
    auth.logout()
    router.push('/login')
  }

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

  onMounted(() => {
    clockInterval = setInterval(() => {
      currentTime.value = new Date()
    }, 60_000)
  })

  onUnmounted(() => clearInterval(clockInterval))
</script>

<template>
  <main class="overview-page">
    <header class="overview-header">
      <router-link aria-label="Northstar home" class="brand" to="/">
        <span class="brand-mark"><span /><span /><span /></span>
        <span>northstar<span class="brand-dot">.</span></span>
      </router-link>

      <nav aria-label="Workspace navigation" class="workspace-nav">
        <router-link class="active" to="/overview">Overview</router-link>
        <router-link to="/employee-communication">Communication</router-link>
        <router-link to="/disaster-management">Disaster response</router-link>
      </nav>

      <button class="account-link" type="button" @click="logout">
        <span class="account-avatar">{{ auth.userFirstName.charAt(0).toUpperCase() }}</span>
        Sign out
      </button>
    </header>

    <div class="overview-content">
      <section class="welcome-panel">
        <div>
          <p class="eyebrow">YOUR NORTHSTAR WORKSPACE</p>
          <h1>{{ greeting }}<br><em>{{ auth.userFirstName }}.</em></h1>

          <p class="welcome-copy">
            A clear view of what’s happening across your organization.
          </p>
        </div>

        <div class="date-card">
          <span class="date-icon"><v-icon icon="mdi-calendar-blank-outline" size="19" /></span>
          <span><small>TODAY</small><strong>{{ formattedDate }}</strong></span>
        </div>
      </section>

      <section aria-label="Workspace summary" class="summary-grid">
        <article class="summary-card">
          <div class="card-topline">
            <span class="card-icon lime"><v-icon icon="mdi-account-group-outline" size="20" /></span>
            <span class="status-label"><span /> ALL SYSTEMS READY</span>
          </div>

          <p class="metric">4,208</p>
          <h2>People in your organization</h2>
          <p class="card-detail">Across 12 teams and locations</p>
        </article>

        <article class="summary-card dark-card">
          <div class="card-topline">
            <span class="card-icon coral"><v-icon icon="mdi-message-text-outline" size="20" /></span>
            <span class="status-label">THIS WEEK</span>
          </div>

          <p class="metric">12</p>
          <h2>Updates shared</h2>
          <p class="card-detail">Keeping every team in the loop</p>
        </article>

        <article class="summary-card">
          <div class="card-topline">
            <span class="card-icon peach"><v-icon icon="mdi-shield-check-outline" size="20" /></span>
            <span class="status-label">RESPONSE STATUS</span>
          </div>

          <p class="metric">Ready</p>
          <h2>Your response workspace</h2>
          <p class="card-detail">Teams and plans are standing by</p>
        </article>
      </section>

      <section class="workspace-section">
        <div class="section-heading">
          <div>
            <p class="eyebrow">YOUR WORKSPACE</p>
            <h2>Where would you like to go?</h2>
          </div>

          <span>Choose a space to get started</span>
        </div>

        <div class="workspace-grid">
          <router-link class="workspace-card communication-card" to="/employee-communication">
            <span class="workspace-icon"><v-icon icon="mdi-message-text-outline" size="22" /></span>

            <span class="workspace-copy">
              <small>EVERYDAY ALIGNMENT</small>
              <strong>Employee communication</strong>
              <span>Share clear updates and keep your people connected.</span>
            </span>

            <v-icon class="workspace-arrow" icon="mdi-arrow-top-right" size="20" />
          </router-link>

          <router-link class="workspace-card response-card" to="/disaster-management">
            <span class="workspace-icon"><v-icon icon="mdi-shield-alert-outline" size="22" /></span>

            <span class="workspace-copy">
              <small>WHEN IT MATTERS MOST</small>
              <strong>Disaster management</strong>
              <span>Coordinate people and actions from one response room.</span>
            </span>

            <v-icon class="workspace-arrow" icon="mdi-arrow-top-right" size="20" />
          </router-link>
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
.welcome-panel {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 24px;
  padding: 65px 0 48px;
}
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
  font-size: clamp(46px, 6vw, 72px);
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
  .overview-header { height: auto; min-height: 72px; flex-wrap: wrap; padding: 14px 20px; }
  .workspace-nav { order: 3; width: 100%; justify-content: space-between; gap: 14px; }
  .workspace-nav a { font-size: 10px; }
  .account-link { font-size: 0; }
  .overview-content { width: min(100% - 40px, 560px); }
  .welcome-panel { align-items: flex-start; flex-direction: column; padding: 48px 0 32px; }
  .welcome-panel h1 { letter-spacing: -2.5px; }
  .date-card { margin: 0; }
  .summary-grid { grid-template-columns: 1fr; gap: 10px; }
  .summary-card { min-height: 178px; }
  .workspace-section { padding: 45px 0; }
  .section-heading { align-items: flex-start; flex-direction: column; }
  .workspace-grid { grid-template-columns: 1fr; }
  .workspace-card { padding: 18px; }
  .overview-footer { flex-direction: column; }
}
</style>
