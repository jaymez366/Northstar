<script setup lang="ts">
  import { ref } from 'vue'

  const submitted = ref(false)

  function submitForm () {
    submitted.value = true
  }
</script>

<template>
  <main class="conversation-page">
    <div class="conversation-layout container">
      <section class="conversation-intro">
        <p class="section-overline">START A CONVERSATION</p>
        <h1>Let’s make<br><em>clarity</em> your<br>next advantage.</h1>

        <p class="intro-copy">
          Tell us a little about your team and we’ll show you how Northstar can
          support communication, continuity, and confident action.
        </p>

        <div class="response-note">
          <span class="response-icon"><v-icon icon="mdi-clock-outline" size="17" /></span>

          <span><strong>Real people, quick replies.</strong>

            <small>We usually respond within one business day.</small></span>
        </div>
      </section>

      <section class="form-panel">
        <div v-if="!submitted">
          <div class="form-heading">
            <span>01 / 02</span>
            <p>Tell us about yourself</p>
          </div>

          <form @submit.prevent="submitForm">
            <label>Work email
              <input
                placeholder="you@company.com"
                required
                type="email"
              ></label>

            <label>Your name <input
              placeholder="Alex Morgan"
              required
              type="text"
            ></label>

            <label>What can we help with?<select required>
              <option disabled selected value="">Choose a focus</option>
              <option>Employee communication</option>
              <option>Disaster management</option>
              <option>Both</option>
            </select></label>

            <label>Anything else we should know?
              <textarea placeholder="A sentence or two is plenty." rows="3" />
            </label>

            <button class="submit-button" type="submit">
              Send inquiry <v-icon icon="mdi-arrow-top-right" size="18" />
            </button>
          </form>

          <p class="privacy-note">
            <v-icon icon="mdi-lock-outline" size="14" /> Your details stay
            private and are only used to reply.
          </p>
        </div>

        <div v-else class="success-state">
          <span class="success-icon"><v-icon
            icon="mdi-check"
            size="28"
          /></span>

          <p class="section-overline">MESSAGE RECEIVED</p>
          <h2>We’ll be in touch<br><em>soon.</em></h2>

          <p>
            Thanks for reaching out. A member of the Northstar team will follow
            up within one business day.
          </p>

          <router-link
            class="return-link"
            to="/overview"
          ><v-icon icon="mdi-arrow-left" size="16" /> Return to
            overview</router-link>
        </div>
      </section>
    </div>

    <footer class="conversation-footer container">
      <span>Internal clarity for external confidence.</span>

      <span>© 2025 Northstar Systems</span>
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
  background: var(--ns-bg-f3f5ef, #f3f5ef);
  color: var(--ns-text-10231d, #10231d);
  font-family: "Manrope", sans-serif;
}
.conversation-page {
  min-height: 100vh;
  background: var(--ns-bg-f3f5ef, #f3f5ef);
}
.container {
  width: min(1160px, calc(100% - 64px));
  margin: 0 auto;
}
.conversation-nav {
  height: 92px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--ns-border-d4ddd1, #d4ddd1);
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
.back-link,
.return-link {
  display: flex;
  align-items: center;
  gap: 9px;
  color: var(--ns-text-60766a, #60766a);
  text-decoration: none;
  font-size: 12px;
  font-weight: 700;
}
.back-link:hover,
.return-link:hover {
  color: var(--ns-text-e16b4c, #e16b4c);
}
.conversation-layout {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 130px;
  padding: 100px 0 110px;
}
.conversation-intro {
  padding-top: 14px;
}
.section-overline,
.form-heading span,
small,
.privacy-note {
  color: var(--ns-text-71897b, #71897b);
  font:
    10px "DM Mono",
    monospace;
  letter-spacing: 1.5px;
}
.conversation-intro h1 {
  margin: 25px 0;
  color: var(--ns-text-18352d, #18352d);
  font-size: clamp(48px, 5.7vw, 78px);
  line-height: 0.99;
  letter-spacing: -4px;
}
.conversation-intro h1 em,
.success-state h2 em {
  color: var(--ns-text-e16b4c, #e16b4c);
  font-style: normal;
}
.intro-copy {
  max-width: 390px;
  color: var(--ns-text-6c7e73, #6c7e73);
  font-size: 14px;
  line-height: 1.8;
}
.response-note {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-top: 58px;
  color: var(--ns-text-18352d, #18352d);
  font-size: 12px;
}
.response-note strong,
.response-note small {
  display: block;
}
.response-note small {
  margin-top: 5px;
  color: var(--ns-text-82958a, #82958a);
  letter-spacing: 0;
}
.response-icon,
.success-icon {
  display: grid;
  place-items: center;
  width: 38px;
  height: 38px;
  background: var(--ns-bg-dce7d5, #dce7d5);
  color: var(--ns-text-e16b4c, #e16b4c);
  border-radius: 50%;
}
.form-panel {
  min-height: 550px;
  padding: 39px 42px;
  background: var(--ns-bg-18352d, #18352d);
  color: var(--ns-text-f3f5ef, #f3f5ef);
  box-shadow: 14px 15px 0 var(--ns-shadow-dce7d5, #dce7d5);
}
.form-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-bottom: 28px;
  border-bottom: 1px solid rgba(243, 245, 239, 0.2);
}
.form-heading p {
  margin: 0;
  color: var(--ns-text-f3f5ef, #f3f5ef);
  font-size: 14px;
  font-weight: 700;
}
form {
  padding-top: 27px;
}
label {
  display: block;
  margin-bottom: 23px;
  color: var(--ns-text-c1d0c5, #c1d0c5);
  font:
    10px "DM Mono",
    monospace;
  letter-spacing: 1px;
}
input,
select,
textarea {
  display: block;
  width: 100%;
  margin-top: 10px;
  padding: 12px 0;
  border: 0;
  border-bottom: 1px solid var(--ns-border-668077, #668077);
  outline: 0;
  background: transparent;
  color: var(--ns-text-f3f5ef, #f3f5ef);
  font:
    14px "Manrope",
    sans-serif;
}
input:focus,
select:focus,
textarea:focus {
  border-color: var(--ns-border-d4ec66, #d4ec66);
}
input::placeholder,
textarea::placeholder {
  color: var(--ns-text-829a8d, #829a8d);
}
select {
  appearance: none;
  background-image:
    linear-gradient(45deg, transparent 50%, #d4ec66 50%),
    linear-gradient(135deg, #d4ec66 50%, transparent 50%);
  background-position:
    calc(100% - 8px) 18px,
    100% 18px;
  background-size:
    7px 7px,
    7px 7px;
  background-repeat: no-repeat;
}
select option {
  color: var(--ns-text-18352d, #18352d);
}
textarea {
  resize: vertical;
}
.submit-button {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  margin-top: 7px;
  padding: 16px 19px;
  border: 0;
  background: var(--ns-bg-d4ec66, #d4ec66);
  color: var(--ns-text-18352d, #18352d);
  font:
    700 12px "Manrope",
    sans-serif;
  cursor: pointer;
}
.submit-button:hover {
  background: var(--ns-bg-e3f48a, #e3f48a);
}
.privacy-note {
  display: flex;
  align-items: center;
  gap: 7px;
  margin: 22px 0 0;
  color: var(--ns-text-829a8d, #829a8d);
  letter-spacing: 0;
}
.success-state {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: center;
  min-height: 465px;
}
.success-icon {
  width: 58px;
  height: 58px;
  margin-bottom: 38px;
  background: var(--ns-bg-d4ec66, #d4ec66);
  color: var(--ns-text-18352d, #18352d);
}
.success-state h2 {
  margin: 21px 0 17px;
  font-size: 44px;
  line-height: 1;
  letter-spacing: -2px;
}
.success-state > p:not(.section-overline) {
  max-width: 300px;
  color: var(--ns-text-b8c9bc, #b8c9bc);
  font-size: 13px;
  line-height: 1.7;
}
.return-link {
  margin-top: 30px;
  color: var(--ns-text-d4ec66, #d4ec66);
}
.conversation-footer {
  display: flex;
  justify-content: space-between;
  padding: 27px 0;
  border-top: 1px solid var(--ns-border-d4ddd1, #d4ddd1);
  color: var(--ns-text-82958a, #82958a);
  font-size: 10px;
}
@media (max-width: 800px) {
  .container {
    width: min(100% - 40px, 560px);
  }
  .conversation-nav {
    height: 74px;
  }
  .conversation-layout {
    display: block;
    padding: 65px 0 80px;
  }
  .conversation-intro h1 {
    letter-spacing: -2.5px;
  }
  .response-note {
    margin-top: 42px;
  }
  .form-panel {
    margin-top: 65px;
    padding: 30px 25px;
  }
  .conversation-footer {
    flex-direction: column;
    gap: 12px;
  }
}
@media (max-width: 420px) {
  .back-link {
    font-size: 0;
  }
  .back-link .v-icon {
    font-size: 20px !important;
  }
  .conversation-intro h1 {
    font-size: 49px;
  }
  .form-panel {
    box-shadow: 8px 9px 0 var(--ns-shadow-dce7d5, #dce7d5);
  }
}
</style>
