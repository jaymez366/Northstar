<script setup lang="ts">
  import { ref } from 'vue'

  const activeTask = ref('Shelter transport')
  const tasks = ['Shelter transport', 'Employee check-in', 'Route assessment']
</script>

<template>
  <main class="response-page">
    <header class="page-header">
      <router-link aria-label="Back to Northstar home" class="brand" to="/">
        <span class="brand-mark"><span /><span /><span /></span>
        <span>northstar<span class="brand-dot">.</span></span>
      </router-link>

      <router-link
        class="back-link"
        to="/overview"
      ><v-icon icon="mdi-arrow-left" size="16" /> Back to
        overview</router-link>
    </header>

    <section class="response-heading">
      <div>
        <p class="eyebrow">
          <span class="live-dot" /> ACTIVE RESPONSE ROOM / 04
        </p>

        <h1>Turn disruption<br><em>into direction.</em></h1>

        <p class="heading-copy">
          Coordinate people, locations, and critical actions from one live
          response room.
        </p>
      </div>

      <div class="incident-status">
        <span class="status-dot" />
        <div><small>INCIDENT STATUS</small><strong>Monitoring</strong></div>
        <span class="incident-time">09:41</span>
      </div>
    </section>

    <section aria-label="Disaster response overview" class="response-grid">
      <div class="map-card">
        <div class="card-heading">
          <div>
            <p class="eyebrow">REGIONAL VIEW</p>
            <h2>North district</h2>
          </div>

          <button
            aria-label="More map options"
            class="icon-button"
            type="button"
          >
            <v-icon icon="mdi-dots-horizontal" />
          </button>
        </div>

        <div class="map-view">
          <div class="map-lines" />
          <div class="route route-a" />
          <div class="route route-b" />

          <span class="map-pin pin-a">1</span>

          <span class="map-pin pin-b">2</span>

          <span class="map-pin pin-c">3</span>

          <div class="map-key">
            <span><i class="safe" /> Safe</span>

            <span><i class="attention" /> Attention</span>
          </div>
        </div>
      </div>

      <aside class="metrics-card">
        <p class="eyebrow">PEOPLE REACHED</p>
        <strong class="metric">12,840</strong>
        <div class="metric-label">of 13,200 employees</div>
        <div class="progress-track"><span /></div>

        <div class="metric-split">
          <div><strong>08</strong><span>open tasks</span></div>
          <div><strong>03</strong><span>safe zones</span></div>
        </div>
      </aside>
    </section>

    <section class="action-section">
      <div class="action-heading">
        <div>
          <p class="eyebrow">RESPONSE CHECKLIST</p>
          <h2>What happens next?</h2>
        </div>

        <span class="completion">4 / 7 COMPLETE</span>
      </div>

      <div class="task-list">
        <button
          v-for="task in tasks"
          :key="task"
          :class="{ selected: activeTask === task }"
          type="button"
          @click="activeTask = task"
        >
          <span class="task-check"><v-icon icon="mdi-check" size="13" /></span>

          <span>{{ task }}</span>

          <v-icon class="task-arrow" icon="mdi-arrow-top-right" size="17" />
        </button>
      </div>

      <div class="task-detail">
        <p class="eyebrow">CURRENT TASK</p>
        <h3>{{ activeTask }}</h3>

        <p>
          Confirm the transport route and update the response room when the team
          is in motion.
        </p>

        <button class="primary-button" type="button">
          Mark as complete <v-icon icon="mdi-check" size="16" />
        </button>
      </div>
    </section>

    <footer class="response-footer">
      <span>Last synchronized 30 seconds ago</span>

      <router-link to="/overview">Return to overview <v-icon
        icon="mdi-arrow-right"
        size="16"
      /></router-link>
    </footer>
  </main>
</template>

<style scoped>
@import url("https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Manrope:wght@400;500;600;700;800&display=swap");

:global(*) {
  box-sizing: border-box;
}
:global(body) {
  margin: 0;
  background: #102d26;
  color: #f5f6ee;
  font-family: "Manrope", sans-serif;
}
.response-page {
  min-height: 100vh;
  padding: 0 max(32px, calc((100vw - 1160px) / 2));
  background: #102d26;
}
.page-header {
  height: 92px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid rgba(239, 243, 229, 0.17);
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  color: #f5f6ee;
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
  width: 5px;  background: #d4ec66;
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
  color: #d4ec66;
}
.back-link {
  color: #c7d2c7;
  text-decoration: none;
  font:
    10px "DM Mono",
    monospace;
  text-transform: uppercase;
  letter-spacing: 1px;
}
.back-link:hover {
  color: #d4ec66;
}
.eyebrow {
  margin: 0;
  color: #8ca295;
  font:
    10px "DM Mono",
    monospace;
  letter-spacing: 1.5px;
}
.response-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  padding: 78px 0 60px;
}
.live-dot,
.status-dot {
  display: inline-block;
  width: 7px;
  height: 7px;
  margin-right: 8px;
  border-radius: 50%;
  background: #e16b4c;
}
.response-heading h1 {
  margin: 23px 0;
  font-size: clamp(44px, 6vw, 72px);
  line-height: 1;
  letter-spacing: -4px;
}
.response-heading em {
  color: #d4ec66;
  font-style: normal;
}
.heading-copy {
  max-width: 400px;
  color: #bac9bd;
  font-size: 15px;
  line-height: 1.8;
}
.incident-status {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 205px;
  padding: 17px 18px;
  border: 1px solid rgba(239, 243, 229, 0.2);
}
.incident-status .status-dot {
  margin: 0;
}
.incident-status small {
  display: block;
  color: #8ca295;
  font:
    8px "DM Mono",
    monospace;
  letter-spacing: 1px;
}
.incident-status strong {
  display: block;
  margin-top: 5px;
  font-size: 13px;
}
.incident-time {
  margin-left: auto;
  align-self: end;
  color: #8ca295;
  font:
    10px "DM Mono",
    monospace;
}
.response-grid {
  display: grid;
  grid-template-columns: 1.35fr 0.65fr;
  gap: 22px;
}
.map-card,
.metrics-card {
  padding: 27px;
  background: #f6f8ee;
  color: #18352d;
}
.card-heading,
.action-heading {
  display: flex;
  align-items: start;
  justify-content: space-between;
}
.card-heading h2,
.action-heading h2 {
  margin: 12px 0 0;
  font-size: 24px;
  letter-spacing: -1px;
}
.card-heading .eyebrow,
.metrics-card .eyebrow {
  color: #6d897b;
}
.icon-button {
  border: 0;
  background: transparent;
  color: #60776b;
  cursor: pointer;
}
.map-view {
  height: 285px;
  position: relative;
  overflow: hidden;
  margin-top: 25px;
  background: #dae3d3;
}
.map-lines {
  position: absolute;
  inset: 0;
  opacity: 0.45;
  background-image:
    linear-gradient(28deg, transparent 48%, #aec2ae 49%, transparent 50%),
    linear-gradient(112deg, transparent 47%, #aec2ae 48%, transparent 49%);
  background-size: 52px 42px;
}
.route {
  position: absolute;
  height: 3px;
  background: #e16b4c;
  transform-origin: left;
}
.route-a {
  width: 260px;
  top: 126px;
  left: 70px;
  transform: rotate(-25deg);
}
.route-b {
  width: 210px;
  top: 174px;
  left: 205px;
  transform: rotate(27deg);
  background: #18352d;
}
.map-pin {
  position: absolute;
  display: grid;
  place-items: center;
  width: 27px;
  height: 27px;
  border: 3px solid #f6f8ee;
  border-radius: 50%;
  background: #e16b4c;
  color: #fff;
  font:
    10px "DM Mono",
    monospace;
  box-shadow: 0 2px 4px #879887;
}
.pin-a {
  top: 93px;
  left: 64px;
}
.pin-b {
  top: 160px;
  left: 200px;
  background: #18352d;
}
.pin-c {
  top: 193px;
  left: 395px;
}
.map-key {
  position: absolute;
  bottom: 14px;
  left: 14px;
  display: flex;
  gap: 15px;
  padding: 8px 10px;
  background: rgba(246, 248, 238, 0.9);
  font:
    8px "DM Mono",
    monospace;
}
.map-key i {
  display: inline-block;
  width: 6px;
  height: 6px;
  margin-right: 4px;
  border-radius: 50%;
}
.safe {
  background: #6eaa69;
}
.attention {
  background: #e16b4c;
}
.metrics-card {
  background: #d4ec66;
}
.metric {
  display: block;
  margin-top: 28px;
  font-size: 45px;
  letter-spacing: -2px;
}
.metric-label {
  margin-top: 5px;
  color: #526854;
  font:
    10px "DM Mono",
    monospace;
}
.progress-track {
  height: 7px;
  margin: 25px 0 40px;
  background: #b6c967;
}
.progress-track span {
  display: block;
  width: 88%;
  height: 100%;
  background: #18352d;
}
.metric-split {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 18px;
}
.metric-split div {
  padding-top: 17px;
  border-top: 1px solid #aec15c;
}
.metric-split strong {
  display: block;
  font-size: 28px;
}
.metric-split span {
  display: block;
  margin-top: 5px;
  color: #526854;
  font:
    9px "DM Mono",
    monospace;
  text-transform: uppercase;
}
.action-section {
  margin: 85px 0 0;
  padding-bottom: 38px;
}
.completion {
  color: #d4ec66;
  font:
    10px "DM Mono",
    monospace;
}
.task-list {
  width: 50%;
  margin-top: 32px;
}
.task-list button {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 13px;
  padding: 17px 0;
  border: 0;
  border-bottom: 1px solid rgba(239, 243, 229, 0.17);
  background: transparent;
  color: #8ca295;
  text-align: left;
  font:
    13px "Manrope",
    sans-serif;
  cursor: pointer;
}
.task-list button.selected {
  color: #f5f6ee;
}
.task-check {
  display: grid;
  place-items: center;
  width: 20px;
  height: 20px;
  border: 1px solid #8ca295;
  border-radius: 50%;
}
.task-list button.selected .task-check {
  border-color: #d4ec66;
  background: #d4ec66;
  color: #18352d;
}
.task-arrow {
  margin-left: auto;
  opacity: 0;
}
.task-list button.selected .task-arrow {
  opacity: 1;
  color: #d4ec66;
}
.task-detail {
  position: absolute;
  width: min(390px, calc(100% - 64px));
  margin: -183px 0 0 calc(50% + 25px);
  padding: 27px;
  background: #f6f8ee;
  color: #18352d;
}
.task-detail .eyebrow {
  color: #e16b4c;
}
.task-detail h3 {
  margin: 13px 0 10px;
  font-size: 21px;
}
.task-detail p:not(.eyebrow) {
  color: #6c7e73;
  font-size: 12px;
  line-height: 1.7;
}
.primary-button {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  margin-top: 14px;
  border: 0;
  padding: 12px 15px;
  background: #18352d;
  color: #f5f6ee;
  font:
    700 10px "Manrope",
    sans-serif;
  cursor: pointer;
}
.response-footer {
  display: flex;
  justify-content: space-between;
  padding: 25px 0 32px;
  border-top: 1px solid rgba(239, 243, 229, 0.17);
  color: #8ca295;
  font:
    10px "DM Mono",
    monospace;
}
.response-footer a {
  color: #d4ec66;
  text-decoration: none;
}
@media (max-width: 720px) {
  .response-page {
    padding: 0 20px;
  }
  .page-header {
    height: 74px;
  }
  .response-heading {
    display: block;
    padding: 62px 0 48px;
  }
  .response-heading h1 {
    letter-spacing: -2.5px;
  }
  .incident-status {
    margin-top: 35px;
  }
  .response-grid {
    display: block;
  }
  .metrics-card {
    margin-top: 18px;
  }
  .map-view {
    height: 230px;
  }
  .task-list {
    width: 100%;
  }
  .task-detail {
    position: static;
    width: 100%;
    margin: 35px 0 0;
  }
  .response-footer {
    align-items: flex-start;
    flex-direction: column;
    gap: 17px;
  }
}
</style>
