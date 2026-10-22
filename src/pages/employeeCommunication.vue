<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'
  import { useWorkspaceStore } from '@/stores/workspace'

  const message = ref('')
  const title = ref('')
  const error = ref('')
  const auth = useAuthStore()
  const workspace = useWorkspaceStore()
  const router = useRouter()
  const canPublishAnnouncement = computed(() => !auth.isAdmin
    && auth.profile.role === 'employee'
    && auth.canAccessEmployeeWorkspace)
  const audienceDepartments = computed(() => workspace.departments.slice(0, 3))
  const recentUpdates = computed(() => workspace.announcements.slice(0, 2))

  async function sendUpdate () {
    error.value = ''
    if (!canPublishAnnouncement.value) {
      error.value = 'Only active Northstar employees can publish announcements.'
      return
    }
    if (!title.value.trim() || !message.value.trim()) {
      error.value = 'Add an announcement title and message before continuing.'
      return
    }
    const published = await workspace.publishAnnouncement(title.value, message.value)
    if (published) {
      router.push('/announcements')
    } else {
      error.value = workspace.backendError || 'Your announcement could not be published.'
    }
  }
</script>

<template>
  <main class="communication-page">
    <section class="page-intro">
      <p class="eyebrow">EMPLOYEE COMMUNICATION</p>
      <h1>Give every employee<br><em>the same signal.</em></h1>

      <p class="intro-copy">
        One calm place to write, target, and measure the updates that keep your
        organization moving together.
      </p>
    </section>

    <section aria-label="Employee communication workspace" class="workspace">
      <div v-if="canPublishAnnouncement" class="composer-panel">
        <div class="panel-heading">
          <div>
            <p class="eyebrow">NEW UPDATE</p>
            <h2>What needs to be said?</h2>
          </div>

          <span class="draft-status">DRAFT</span>
        </div>

        <label for="update-title">Announcement title</label>

        <input
          id="update-title"
          v-model="title"
          class="update-title"
          maxlength="90"
          placeholder="Announcement title"
          type="text"
        >

        <label for="update-message">Message</label>

        <textarea
          id="update-message"
          v-model="message"
          maxlength="500"
          placeholder="Write a clear update for your people..."
          rows="7"
        />

        <p v-if="error" class="form-error" role="alert">{{ error }}</p>

        <div class="composer-footer">
          <span class="character-count">{{ message.length }} / 500</span>

          <button class="send-button" type="button" @click="sendUpdate">
            Publish update <v-icon icon="mdi-arrow-right" size="17" />
          </button>
        </div>
      </div>

      <div v-else class="composer-panel">
        <p class="form-error" role="status">Announcement publishing is available to active employees only.</p>
      </div>

      <aside class="insight-panel">
        <p class="eyebrow">REACH AT A GLANCE</p>
        <div class="reach-number">{{ workspace.employees.length }} <span>people</span></div>
        <div class="reach-bar" :style="{ opacity: workspace.employees.length > 0 ? 1 : 0.35 }"><span /></div>

        <div class="reach-meta">
          <span>Active profiles</span><span>{{ workspace.departments.length }} departments</span>
        </div>

        <div class="audience-list">
          <div v-for="(department, index) in audienceDepartments" :key="department.name">
            <span class="audience-dot" :class="['lime', 'coral', 'dark'][index]" />
            <span>{{ department.name }}</span>
            <strong>{{ department.count }}</strong>
          </div>
        </div>
      </aside>
    </section>

    <section class="recent-section">
      <div class="section-heading">
        <div>
          <p class="eyebrow">RECENT UPDATES</p>
          <h2>Keep the rhythm.</h2>
        </div>

        <span class="live-label"><span /> PUBLISHED UPDATES</span>
      </div>

      <div v-for="update in recentUpdates" :key="update.id" class="update-row">
        <span class="update-time">{{ new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(update.createdAt)) }}</span>

        <div>
          <strong>{{ update.title }}</strong>
          <p>{{ update.description }}</p>
        </div>

        <span class="delivered"><v-icon icon="mdi-check-circle" size="15" /> Published</span>
      </div>

      <p v-if="recentUpdates.length === 0" class="no-updates">No announcements have been published yet.</p>
    </section>
  </main>
</template>

<style scoped>
@import url("https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Manrope:wght@400;500;600;700;800&display=swap");

:global(*) {
  box-sizing: border-box;
}
:global(body) {
  margin: 0;
  background: var(--ns-bg-f3f5ef, #f3f5ef);
  color: var(--ns-text-10231d, #10231d);
  font-family: "Manrope", sans-serif;
}
.communication-page {
  min-height: 100vh;
  padding: 0;
  background: var(--ns-bg-f3f5ef, #f3f5ef);
}
.page-header {
  height: 92px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--ns-border-cdd6ca, #cdd6ca);
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--ns-text-18352d, #18352d);
  text-decoration: none;
  font-size: 20px;
  font-weight: 800;
  letter-spacing: -1px;
}
.brand-mark {
  display: flex;
  align-items: end;
  gap: 2px;
  height: 20px;
}
.brand-mark span {
  display: block;
  width: 5px;
  background: var(--ns-bg-e16b4c, #e16b4c);
  border-radius: 1px;
}
.brand-mark span:nth-child(1) {
  height: 11px;
}
.brand-mark span:nth-child(2) {
  height: 17px;
}
.brand-mark span:nth-child(3) {
  height: 14px;
}
.brand-dot {
  color: var(--ns-text-e16b4c, #e16b4c);
}
.back-link {
  color: var(--ns-text-60776b, #60776b);
  text-decoration: none;
  font:
    10px "DM Mono",
    monospace;
  text-transform: uppercase;
  letter-spacing: 1px;
}
.back-link:hover {
  color: var(--ns-text-e16b4c, #e16b4c);
}
.eyebrow {
  margin: 0;
  color: var(--ns-text-6d897b, #6d897b);
  font:
    10px "DM Mono",
    monospace;
  letter-spacing: 1.5px;
}
.page-intro {
  padding: 82px 0 65px;
  max-width: 720px;
}
.page-intro h1 {
  margin: 22px 0;
  font-size: clamp(42px, 6vw, 72px);
  line-height: 1.02;
  letter-spacing: -4px;
}
.page-intro em {
  color: var(--ns-text-e16b4c, #e16b4c);
  font-style: normal;
}
.intro-copy {
  max-width: 440px;
  color: var(--ns-text-6c7e73, #6c7e73);
  font-size: 15px;
  line-height: 1.8;
}
.workspace {
  display: grid;
  grid-template-columns: 1.35fr 0.65fr;
  gap: 24px;
}
.composer-panel,
.insight-panel {
  padding: 32px;
  border: 1px solid var(--ns-border-cdd6ca, #cdd6ca);
  background: var(--ns-bg-fffdf5, #fffdf5);
}
.panel-heading {
  display: flex;
  align-items: start;
  justify-content: space-between;
  margin-bottom: 37px;
}
.panel-heading h2 {
  margin: 12px 0 0;
  font-size: 25px;
  letter-spacing: -1px;
}
.draft-status {
  padding: 7px 9px;
  background: var(--ns-bg-eaf0df, #eaf0df);
  color: var(--ns-text-6d897b, #6d897b);
  font:
    9px "DM Mono",
    monospace;
  letter-spacing: 1px;
}
label {
  display: block;
  margin-bottom: 9px;
  color: var(--ns-text-6d897b, #6d897b);
  font:
    10px "DM Mono",
    monospace;
  text-transform: uppercase;
}
textarea {
  width: 100%;
  resize: vertical;
  border: 1px solid var(--ns-border-cdd6ca, #cdd6ca);
  padding: 16px;
  background: var(--ns-bg-f3f5ef, #f3f5ef);
  color: var(--ns-text-18352d, #18352d);
  font:
    14px/1.7 "Manrope",
    sans-serif;
  outline: none;
}
.update-title {
  width: 100%;
  margin-bottom: 12px;
  border: 1px solid var(--ns-border-cdd6ca, #cdd6ca);
  padding: 13px 15px;
  color: var(--ns-text-18352d, #18352d);
  font: 600 12px "Manrope", sans-serif;
}
.form-error { color: var(--ns-text-b85138, #b85138); font-size: 10px; }
textarea:focus {
  border-color: var(--ns-border-e16b4c, #e16b4c);
}
.composer-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 18px;
}
.character-count {
  color: var(--ns-text-8aa092, #8aa092);
  font:
    10px "DM Mono",
    monospace;
}
.send-button {
  display: inline-flex;
  align-items: center;
  gap: 12px;
  border: 0;
  padding: 13px 17px;
  background: var(--ns-bg-18352d, #18352d);
  color: var(--ns-text-f5f6ee, #f5f6ee);
  font:
    700 11px "Manrope",
    sans-serif;
  cursor: pointer;
}
.send-button:hover {
  background: var(--ns-bg-e16b4c, #e16b4c);
}
.insight-panel {
  background: var(--ns-bg-dce7d5, #dce7d5);
}
.insight-panel > .eyebrow {
  color: var(--ns-text-61756a, #61756a);
}
.reach-number {
  margin: 27px 0 18px;
  font-size: 42px;
  font-weight: 700;
  letter-spacing: -2px;
}
.reach-number span {
  color: var(--ns-text-6c8074, #6c8074);
  font:
    10px "DM Mono",
    monospace;
  letter-spacing: 0;
}
.reach-bar {
  height: 7px;
  background: var(--ns-bg-bdcdb9, #bdcdb9);
}
.reach-bar span {
  display: block;
  width: 94%;
  height: 100%;
  background: var(--ns-bg-e16b4c, #e16b4c);
}
.reach-meta {
  display: flex;
  justify-content: space-between;
  margin-top: 10px;
  color: var(--ns-text-6c8074, #6c8074);
  font:
    10px "DM Mono",
    monospace;
}
.audience-list {
  margin-top: 54px;
}
.audience-list div {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 14px 0;
  border-bottom: 1px solid var(--ns-border-c1d0bc, #c1d0bc);
  color: var(--ns-text-61756a, #61756a);
  font-size: 12px;
}
.audience-list strong {
  margin-left: auto;
  color: var(--ns-text-18352d, #18352d);
  font:
    12px "DM Mono",
    monospace;
}
.audience-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
}
.lime {
  background: var(--ns-bg-a2bf55, #a2bf55);
}
.coral {
  background: var(--ns-bg-e16b4c, #e16b4c);
}
.dark {
  background: var(--ns-bg-18352d, #18352d);
}
.recent-section {
  padding: 105px 0 90px;
}
.section-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  padding-bottom: 23px;
  border-bottom: 1px solid var(--ns-border-cdd6ca, #cdd6ca);
}
.section-heading h2 {
  margin: 14px 0 0;
  font-size: 34px;
  letter-spacing: -1.5px;
}
.live-label {
  color: var(--ns-text-6d897b, #6d897b);
  font:
    10px "DM Mono",
    monospace;
}
.live-label span {
  display: inline-block;
  width: 6px;
  height: 6px;
  margin-right: 7px;
  border-radius: 50%;
  background: var(--ns-bg-a2bf55, #a2bf55);
}
.update-row {
  display: grid;
  grid-template-columns: 120px 1fr auto;
  gap: 30px;
  align-items: center;
  padding: 23px 0;
  border-bottom: 1px solid var(--ns-border-cdd6ca, #cdd6ca);
}
.update-time {
  color: var(--ns-text-8aa092, #8aa092);
  font:
    9px/1.8 "DM Mono",
    monospace;
}
.update-time strong {
  color: var(--ns-text-18352d, #18352d);
  font-weight: 400;
}
.update-row > div strong {
  font-size: 14px;
}
.update-row p {
  margin: 5px 0 0;
  color: var(--ns-text-718479, #718479);
  font-size: 12px;
}
.delivered {
  color: var(--ns-text-6d897b, #6d897b);
  font:
    10px "DM Mono",
    monospace;
}
@media (max-width: 720px) {
  .communication-page {
    padding: 0 20px;
  }
  .page-header {
    height: 74px;
  }
  .page-intro {
    padding: 62px 0 48px;
  }
  .page-intro h1 {
    letter-spacing: -2.5px;
  }
  .workspace {
    display: block;
  }
  .insight-panel {
    margin-top: 18px;
  }
  .recent-section {
    padding-top: 75px;
  }
  .update-row {
    grid-template-columns: 75px 1fr;
    gap: 14px;
  }
  .delivered {
    grid-column: 2;
  }
  .section-heading {
    align-items: start;
    flex-direction: column;
    gap: 22px;
  }
}
</style>
