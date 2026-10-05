<script setup lang="ts">
  import { ref } from 'vue'

  const message = ref('')
  function sendUpdate () {
    message.value = ''
  }
</script>

<template>
  <main class="communication-page">
    <header class="page-header">
      <router-link aria-label="Back to Northstar home" class="brand" to="/">
        <span class="brand-mark"><span /><span /><span /></span>
        <span>northstar<span class="brand-dot">.</span></span>
      </router-link>

      <router-link class="back-link" to="/overview">
        <v-icon icon="mdi-arrow-left" size="16" /> Back to overview
      </router-link>
    </header>

    <section class="page-intro">
      <p class="eyebrow">EMPLOYEE COMMUNICATION</p>
      <h1>Give every employee<br><em>the same signal.</em></h1>

      <p class="intro-copy">
        One calm place to write, target, and measure the updates that keep your
        organization moving together.
      </p>
    </section>

    <section aria-label="Employee communication workspace" class="workspace">
      <div class="composer-panel">
        <div class="panel-heading">
          <div>
            <p class="eyebrow">NEW UPDATE</p>
            <h2>What needs to be said?</h2>
          </div>

          <span class="draft-status">DRAFT</span>
        </div>

        <label for="update-message">Message</label>

        <textarea
          id="update-message"
          v-model="message"
          placeholder="Write a clear update for your people..."
          rows="7"
        />

        <div class="composer-footer">
          <span class="character-count">{{ message.length }} / 500</span>

          <button class="send-button" type="button" @click="sendUpdate">
            Continue <v-icon icon="mdi-arrow-right" size="17" />
          </button>
        </div>
      </div>

      <aside class="insight-panel">
        <p class="eyebrow">REACH AT A GLANCE</p>
        <div class="reach-number">4,208 <span>people</span></div>
        <div class="reach-bar"><span /></div>

        <div class="reach-meta">
          <span>98% opted in</span><span>Across 12 teams</span>
        </div>

        <div class="audience-list">
          <div>
            <span class="audience-dot lime" />

            <span>All employees</span>

            <strong>3,842</strong>
          </div>

          <div>
            <span class="audience-dot coral" />

            <span>Managers</span>

            <strong>284</strong>
          </div>

          <div>
            <span class="audience-dot dark" />

            <span>On-call teams</span>

            <strong>82</strong>
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

        <span class="live-label"><span /> LIVE DELIVERY</span>
      </div>

      <div class="update-row">
        <span class="update-time">TODAY<br><strong>09:41</strong></span>

        <div>
          <strong>Severe weather protocol</strong>
          <p>All clear update sent to the organization.</p>
        </div>

        <span class="delivered"><v-icon icon="mdi-check-circle" size="15" /> Delivered</span>
      </div>

      <div class="update-row">
        <span class="update-time">YESTERDAY<br><strong>16:20</strong></span>

        <div>
          <strong>Quarterly town hall reminder</strong>
          <p>Sent to 1,642 employees across 8 teams.</p>
        </div>

        <span class="delivered"><v-icon icon="mdi-check-circle" size="15" /> Delivered</span>
      </div>
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
  background: #f3f5ef;
  color: #10231d;
  font-family: "Manrope", sans-serif;
}
.communication-page {
  min-height: 100vh;
  padding: 0 max(32px, calc((100vw - 1160px) / 2));
  background: #f3f5ef;
}
.page-header {
  height: 92px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid #cdd6ca;
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
.brand-mark {
  display: flex;
  align-items: end;
  gap: 2px;
  height: 20px;
}
.brand-mark span {
  display: block;
  width: 5px;
  background: #e16b4c;
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
  color: #e16b4c;
}
.back-link {
  color: #60776b;
  text-decoration: none;
  font:
    10px "DM Mono",
    monospace;
  text-transform: uppercase;
  letter-spacing: 1px;
}
.back-link:hover {
  color: #e16b4c;
}
.eyebrow {
  margin: 0;
  color: #6d897b;
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
  color: #e16b4c;
  font-style: normal;
}
.intro-copy {
  max-width: 440px;
  color: #6c7e73;
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
  border: 1px solid #cdd6ca;
  background: #fffdf5;
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
  background: #eaf0df;
  color: #6d897b;
  font:
    9px "DM Mono",
    monospace;
  letter-spacing: 1px;
}
label {
  display: block;
  margin-bottom: 9px;
  color: #6d897b;
  font:
    10px "DM Mono",
    monospace;
  text-transform: uppercase;
}
textarea {
  width: 100%;
  resize: vertical;
  border: 1px solid #cdd6ca;
  padding: 16px;
  background: #f3f5ef;
  color: #18352d;
  font:
    14px/1.7 "Manrope",
    sans-serif;
  outline: none;
}
textarea:focus {
  border-color: #e16b4c;
}
.composer-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 18px;
}
.character-count {
  color: #8aa092;
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
  background: #18352d;
  color: #f5f6ee;
  font:
    700 11px "Manrope",
    sans-serif;
  cursor: pointer;
}
.send-button:hover {
  background: #e16b4c;
}
.insight-panel {
  background: #dce7d5;
}
.insight-panel > .eyebrow {
  color: #61756a;
}
.reach-number {
  margin: 27px 0 18px;
  font-size: 42px;
  font-weight: 700;
  letter-spacing: -2px;
}
.reach-number span {
  color: #6c8074;
  font:
    10px "DM Mono",
    monospace;
  letter-spacing: 0;
}
.reach-bar {
  height: 7px;
  background: #bdcdb9;
}
.reach-bar span {
  display: block;
  width: 94%;
  height: 100%;
  background: #e16b4c;
}
.reach-meta {
  display: flex;
  justify-content: space-between;
  margin-top: 10px;
  color: #6c8074;
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
  border-bottom: 1px solid #c1d0bc;
  color: #61756a;
  font-size: 12px;
}
.audience-list strong {
  margin-left: auto;
  color: #18352d;
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
  background: #a2bf55;
}
.coral {
  background: #e16b4c;
}
.dark {
  background: #18352d;
}
.recent-section {
  padding: 105px 0 90px;
}
.section-heading {
  display: flex;
  align-items: end;
  justify-content: space-between;
  padding-bottom: 23px;
  border-bottom: 1px solid #cdd6ca;
}
.section-heading h2 {
  margin: 14px 0 0;
  font-size: 34px;
  letter-spacing: -1.5px;
}
.live-label {
  color: #6d897b;
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
  background: #a2bf55;
}
.update-row {
  display: grid;
  grid-template-columns: 120px 1fr auto;
  gap: 30px;
  align-items: center;
  padding: 23px 0;
  border-bottom: 1px solid #cdd6ca;
}
.update-time {
  color: #8aa092;
  font:
    9px/1.8 "DM Mono",
    monospace;
}
.update-time strong {
  color: #18352d;
  font-weight: 400;
}
.update-row > div strong {
  font-size: 14px;
}
.update-row p {
  margin: 5px 0 0;
  color: #718479;
  font-size: 12px;
}
.delivered {
  color: #6d897b;
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
