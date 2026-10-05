<script setup lang="ts">
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const router = useRouter()

  function logout () {
    auth.logout()
    router.push('/login')
  }
</script>

<template>
  <main class="site-shell">
    <section id="top" class="hero">
      <nav aria-label="Main navigation" class="nav container">
        <a aria-label="Northstar home" class="brand" href="#top">
          <span class="brand-mark"><span /><span /><span /></span>
          <span>northstar<span class="brand-dot">.</span></span>
        </a>

        <div class="nav-links">
          <a href="#solutions">Solutions</a>
          <a href="#outcomes">Outcomes</a>
          <a href="#about">About</a>
        </div>

        <router-link
          class="nav-cta"
          to="/start-conversation"
        >Talk to an expert <v-icon
          icon="mdi-arrow-top-right"
          size="16"
        /></router-link>

        <button
          v-if="auth.isAuthenticated"
          class="nav-login"
          type="button"
          @click="logout"
        >Sign out</button>

        <router-link
          v-else
          class="nav-login"
          to="/login"
        >Sign in</router-link>
      </nav>

      <div class="hero-grid container">
        <div class="hero-copy">
          <div class="kicker">
            <span class="pulse" /> Built for business continuity
          </div>

          <h1>When the stakes are high, <em>clarity</em> moves first.</h1>

          <p class="hero-lede">
            Northstar gives modern organizations the confidence to communicate
            clearly, respond quickly, and keep people moving forward.
          </p>

          <div class="hero-actions">
            <router-link
              class="button button-primary"
              to="/start-conversation"
            >See Northstar in action <v-icon
              icon="mdi-arrow-right"
              size="18"
            /></router-link>

            <a
              class="text-link"
              href="#solutions"
            >Explore solutions <v-icon
              icon="mdi-arrow-down"
              size="18"
            /></a>
          </div>

          <div class="trust-row">
            <span>Trusted by teams at</span>

            <strong>ACME</strong>

            <strong>WAYFINDER</strong><strong>vertex</strong>
          </div>
        </div>

        <div
          aria-label="Northstar incident response dashboard preview"
          class="hero-visual"
        >
          <div class="visual-label">LIVE OPERATIONS VIEW <span /></div>

          <div class="dashboard-card">
            <div class="dashboard-top">
              <span class="mini-brand">N<span>•</span></span>

              <span>Response room / 04</span>

              <v-icon icon="mdi-dots-horizontal" />
            </div>

            <div class="incident-title">
              <span class="status-dot" />

              <div>
                <small>ACTIVE INCIDENT</small>

                <strong>Severe weather protocol</strong>
              </div>

              <span class="time">09:41</span>
            </div>

            <div class="map-panel">
              <div class="map-grid" />
              <div class="map-route route-one" />
              <div class="map-route route-two" />

              <span class="map-pin pin-one">1</span>

              <span class="map-pin pin-two">2</span>

              <span class="map-pin pin-three">3</span>

              <div class="map-legend">
                <span><i class="green-dot" /> Safe zones</span>

                <span><i class="orange-dot" /> Attention</span>
              </div>
            </div>

            <div class="dashboard-bottom">
              <div><small>PEOPLE REACHED</small><strong>12,840</strong></div>

              <div>
                <small>OPEN TASKS</small><strong>08 <span>/ 24</span></strong>
              </div>

              <div class="avatar-stack">
                <span>JD</span><span>MK</span><span>+9</span>
              </div>
            </div>
          </div>

          <div class="floating-note">
            <span class="check-icon"><v-icon
              icon="mdi-check"
              size="13"
            /></span>

            <div>
              <strong>All clear update sent</strong>

              <small>To 4,208 employees · just now</small>
            </div>
          </div>
        </div>
      </div>

      <div class="hero-footer container">
        <span>Scroll to discover</span>
        <div class="footer-line" />
        <span>01 / 03</span>
      </div>
    </section>

    <section id="outcomes" class="intro-band">
      <div class="container intro-grid">
        <p class="section-overline">THE NORTHSTAR DIFFERENCE</p>
        <h2>Prepared teams make <span>better decisions.</span></h2>

        <p class="intro-text">
          The tools you use to communicate internally should be as considered as
          the way you run your business. Simple enough for everyone. Powerful
          enough for anything.
        </p>
      </div>
    </section>

    <section id="solutions" class="solutions-section container">
      <div class="section-heading">
        <div>
          <p class="section-overline">ONE PLATFORM. TWO MOMENTS.</p>
          <h2>Clarity, <span>on demand.</span></h2>
        </div>

        <p>
          From everyday alignment to exceptional events, Northstar helps people
          know what is happening and what to do next.
        </p>
      </div>

      <div class="solution-layout">
        <div class="solution-switcher">
          <router-link
            class="solution-link active"
            to="/employee-communication"
          ><span>01</span>
            Employee communication
            <v-icon
              icon="mdi-arrow-top-right"
              size="18"
            /></router-link>

          <router-link
            class="solution-link"
            to="/disaster-management"
          ><span>02</span>
            Disaster management
            <v-icon
              icon="mdi-arrow-top-right"
              size="18"
            /></router-link>

          <div class="solution-note">
            Designed around how people actually behave under pressure.
          </div>
        </div>

        <div class="solution-details">
          <article class="solution-detail">
            <p class="solution-eyebrow">EMPLOYEE COMMS</p>
            <h3>Keep every team in the loop.</h3>

            <p>
              Targeted updates, read receipts, and a calm single source of truth
              for the moments that matter.
            </p>

            <div class="detail-metric">
              <strong>94%</strong><span>message reach in 6 min</span>
            </div>
          </article>

          <article class="solution-detail response-detail">
            <p class="solution-eyebrow">DISASTER RESPONSE</p>
            <h3>Turn disruption into direction.</h3>

            <p>
              Coordinate people, locations, and critical actions from one live
              response room.
            </p>

            <div class="detail-metric">
              <strong>08:42</strong><span>average time to first update</span>
            </div>
          </article>
        </div>
      </div>
    </section>

    <section id="contact" class="contact-band">
      <div class="container contact-content">
        <div>
          <p class="section-overline">READY WHEN YOU ARE</p>
          <h2>Make your next move<br><em>the clear one.</em></h2>
        </div>

        <router-link
          class="button button-light"
          to="/start-conversation"
        >Start a conversation <v-icon
          icon="mdi-arrow-top-right"
          size="18"
        /></router-link>
      </div>
    </section>

    <footer id="about" class="footer container">
      <a
        class="brand"
        href="#top"
      ><span class="brand-mark"><span /><span /><span /></span>

        <span>northstar<span class="brand-dot">.</span></span></a>

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
:global(html) {
  scroll-behavior: smooth;
}
:global(body) {
  margin: 0;
  background: #f3f5ef;
  color: #10231d;
  font-family: "Manrope", sans-serif;
}
.site-shell {
  overflow: hidden;
}
.container {
  width: min(1160px, calc(100% - 64px));
  margin: 0 auto;
}
.hero {
  min-height: 720px;
  background: #102d26;
  color: #f5f6ee;
  position: relative;
  isolation: isolate;
}
.hero::after {
  content: "";
  position: absolute;
  inset: auto 0 0;
  height: 220px;
  opacity: 0.12;
  background-image:
    linear-gradient(
      90deg,
      transparent 49.5%,
      #cbd9c7 49.5%,
      #cbd9c7 50.5%,
      transparent 50.5%
    ),
    linear-gradient(#cbd9c7 1px, transparent 1px);
  background-size: 72px 72px;
  mask-image: linear-gradient(transparent, #000);
  z-index: -1;
}
.nav {
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
  color: inherit;
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
  background: #d4ec66;
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
.nav-links {
  display: flex;
  gap: 36px;
  margin-left: 120px;
}
.nav-links a,
.nav-cta,
.nav-login {
  color: #c7d2c7;
  text-decoration: none;
  font-size: 12px;
  font-weight: 600;
}
.nav-links a:hover,
.nav-cta:hover,
.nav-login:hover {
  color: #d4ec66;
}
.nav-cta {
  display: flex;
  align-items: center;
  gap: 9px;
  color: #f5f6ee;
}
.nav-login {
  border: 0;
  padding: 0;
  background: transparent;
  cursor: pointer;
  font-family: inherit;
}
.hero-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 74px;
  padding-top: 90px;
}
.hero-copy {
  max-width: 580px;
}
.kicker,
.section-overline,
.visual-label,
small {
  font-family: "DM Mono", monospace;
  letter-spacing: 1.5px;
  font-size: 10px;
}
.kicker {
  color: #d4ec66;
  display: flex;
  align-items: center;
  gap: 10px;
}
.pulse {
  display: inline-block;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #d4ec66;
  box-shadow: 0 0 0 5px rgba(212, 236, 102, 0.12);
}
h1 {
  max-width: 620px;
  margin: 25px 0 25px;
  font-size: clamp(44px, 5.2vw, 76px);
  line-height: 1.02;
  letter-spacing: -4px;
  font-weight: 700;
}
.hero h1 em,
h2 span,
.contact-band em {
  color: #d4ec66;
  font-style: normal;
}
.hero-lede {
  color: #bac9bd;
  max-width: 450px;
  font-size: 16px;
  line-height: 1.7;
}
.hero-actions {
  display: flex;
  align-items: center;
  gap: 26px;
  margin-top: 34px;
}
.button {
  display: inline-flex;
  align-items: center;
  gap: 14px;
  padding: 15px 20px;
  text-decoration: none;
  font-size: 12px;
  font-weight: 700;
}
.button-primary {
  background: #d4ec66;
  color: #102d26;
}
.button-light {
  background: #f3f5ef;
  color: #102d26;
}
.text-link {
  color: #eff3e5;
  text-decoration: none;
  font-size: 12px;
  font-weight: 700;
}
.text-link:hover {
  color: #d4ec66;
}
.trust-row {
  display: flex;
  align-items: center;
  gap: 19px;
  margin-top: 79px;
  color: #71877a;
  font-size: 10px;
}
.trust-row strong {
  color: #99aaa0;
  font-size: 11px;
  letter-spacing: 1px;
}
.hero-visual {
  position: relative;
  padding-top: 23px;
}
.visual-label {
  position: absolute;
  top: 0;
  right: 2px;
  color: #8ca295;
}
.visual-label span {
  display: inline-block;
  width: 6px;
  height: 6px;
  margin-left: 8px;
  border-radius: 50%;
  background: #e16b4c;
}
.dashboard-card {
  background: #f6f8ee;
  color: #18352d;
  box-shadow: 18px 22px 0 rgba(7, 22, 18, 0.27);
  padding: 20px;
  transform: rotate(2.2deg);
}
.dashboard-top,
.incident-title,
.dashboard-bottom {
  display: flex;
  align-items: center;
}
.dashboard-top {
  justify-content: space-between;
  font:
    10px "DM Mono",
    monospace;
  color: #779085;
}
.mini-brand {
  background: #18352d;
  color: #f6f8ee;
  padding: 7px;
  font-weight: 800;
}
.mini-brand span {
  color: #d4ec66;
}
.incident-title {
  gap: 10px;
  margin: 25px 0 18px;
}
.incident-title small,
.dashboard-bottom small {
  display: block;
  color: #85988e;
  font-size: 8px;
}
.incident-title strong {
  display: block;
  margin-top: 5px;
  font-size: 16px;
}
.status-dot {
  width: 9px;
  height: 9px;
  background: #e16b4c;
  border-radius: 50%;
}
.time {
  margin-left: auto;
  align-self: end;
  color: #779085;
  font:
    10px "DM Mono",
    monospace;
}
.map-panel {
  height: 236px;
  position: relative;
  overflow: hidden;
  background: #dae3d3;
}
.map-grid {
  position: absolute;
  inset: 0;
  opacity: 0.45;
  background-image:
    linear-gradient(28deg, transparent 48%, #aec2ae 49%, transparent 50%),
    linear-gradient(112deg, transparent 47%, #aec2ae 48%, transparent 49%);
  background-size: 42px 36px;
}
.map-route {
  position: absolute;
  height: 2px;
  background: #e16b4c;
  transform-origin: left;
}
.route-one {
  width: 210px;
  top: 104px;
  left: 50px;
  transform: rotate(-27deg);
}
.route-two {
  width: 170px;
  top: 142px;
  left: 154px;
  transform: rotate(28deg);
  background: #18352d;
}
.map-pin {
  position: absolute;
  display: grid;
  place-items: center;
  width: 23px;
  height: 23px;
  border: 3px solid #f6f8ee;
  border-radius: 50%;
  background: #e16b4c;
  color: #fff;
  font:
    10px "DM Mono",
    monospace;
  box-shadow: 0 2px 4px #879887;
}
.pin-one {
  top: 80px;
  left: 43px;
}
.pin-two {
  top: 130px;
  left: 150px;
  background: #18352d;
}
.pin-three {
  top: 157px;
  left: 308px;
}
.map-legend {
  position: absolute;
  bottom: 12px;
  left: 12px;
  display: flex;
  gap: 15px;
  padding: 7px 9px;
  background: rgba(246, 248, 238, 0.88);
  font:
    8px "DM Mono",
    monospace;
}
.map-legend i {
  display: inline-block;
  width: 6px;
  height: 6px;
  margin-right: 4px;
  border-radius: 50%;
}
.green-dot {
  background: #6eaa69;
}
.orange-dot {
  background: #e16b4c;
}
.dashboard-bottom {
  justify-content: space-between;
  padding-top: 20px;
}
.dashboard-bottom strong {
  display: block;
  margin-top: 6px;
  font-size: 22px;
}
.dashboard-bottom strong span {
  color: #9aac9f;
  font-size: 12px;
}
.avatar-stack {
  display: flex;
  align-items: center;
}
.avatar-stack span {
  display: grid;
  place-items: center;
  width: 26px;
  height: 26px;
  margin-left: -5px;
  border: 2px solid #f6f8ee;
  border-radius: 50%;
  background: #d4ec66;
  color: #18352d;
  font:
    8px "DM Mono",
    monospace;
}
.avatar-stack span:nth-child(2) {
  background: #e3a88d;
}
.avatar-stack span:nth-child(3) {
  background: #18352d;
  color: white;
}
.floating-note {
  position: absolute;
  bottom: 13px;
  left: -40px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 13px 17px;
  background: #fffdf5;
  color: #18352d;
  box-shadow: 7px 8px 0 rgba(7, 22, 18, 0.18);
  transform: rotate(-3deg);
}
.check-icon {
  display: grid;
  place-items: center;
  width: 25px;
  height: 25px;
  background: #d4ec66;
  border-radius: 50%;
}
.floating-note strong,
.floating-note small {
  display: block;
  font-size: 10px;
}
.floating-note small {
  margin-top: 3px;
  color: #809289;
  letter-spacing: 0;
}
.hero-footer {
  display: flex;
  align-items: center;
  gap: 19px;
  padding-top: 65px;
  color: #70877a;
  font:
    10px "DM Mono",
    monospace;
}
.footer-line {
  width: 44px;
  height: 1px;
  background: #71877a;
}
.intro-band {
  padding: 125px 0 112px;
  background: #f3f5ef;
}
.intro-grid {
  display: grid;
  grid-template-columns: 1fr 1.3fr 1fr;
  gap: 55px;
  align-items: start;
}
.section-overline {
  margin: 4px 0 0;
  color: #6d897b;
}
.intro-band h2,
.section-heading h2 {
  margin: 0;
  font-size: clamp(34px, 4vw, 54px);
  line-height: 1.05;
  letter-spacing: -2.5px;
}
.intro-text,
.section-heading > p {
  margin: 4px 0 0;
  color: #6c7e73;
  font-size: 13px;
  line-height: 1.8;
}
.solutions-section {
  padding-bottom: 135px;
}
.section-heading {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 100px;
  align-items: end;
  border-top: 1px solid #cdd6ca;
  padding-top: 28px;
}
.section-heading > p {
  max-width: 330px;
}
.solution-layout {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 110px;
  margin-top: 80px;
}
.solution-switcher button {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 17px;
  padding: 22px 0;
  border: 0;
  border-bottom: 1px solid #cdd6ca;
  background: transparent;
  color: #8aa092;
  text-align: left;
  font:
    600 16px "Manrope",
    sans-serif;
  cursor: pointer;
}
.solution-switcher button span {
  color: #8aa092;
  font:
    10px "DM Mono",
    monospace;
}
.solution-switcher button .v-icon {
  margin-left: auto;
  opacity: 0;
}
.solution-switcher button.active {
  color: #18352d;
}
.solution-switcher button.active span {
  color: #e16b4c;
}
.solution-switcher button.active .v-icon {
  opacity: 1;
}
.solution-note {
  margin-top: 39px;
  color: #84968b;
  font:
    10px/1.6 "DM Mono",
    monospace;
  max-width: 220px;
}
.solution-detail {
  background: #dce7d5;
  padding: 45px;
  min-height: 300px;
}
.solution-eyebrow {
  color: #e16b4c;
  font:
    10px "DM Mono",
    monospace;
  letter-spacing: 1.5px;
}
.solution-detail h3 {
  max-width: 340px;
  margin: 28px 0 15px;
  font-size: 31px;
  line-height: 1.1;
  letter-spacing: -1.4px;
}
.solution-detail > p:not(.solution-eyebrow) {
  max-width: 360px;
  color: #61756a;
  font-size: 13px;
  line-height: 1.7;
}
.detail-metric {
  display: flex;
  align-items: baseline;
  gap: 13px;
  margin-top: 28px;
}
.detail-metric strong {
  font-size: 35px;
  letter-spacing: -2px;
}
.detail-metric span {
  color: #6c8074;
  font:
    10px "DM Mono",
    monospace;
}
.contact-band {
  background: #e16b4c;
  color: #fff7ee;
  padding: 93px 0 88px;
}
.contact-content {
  display: flex;
  justify-content: space-between;
  align-items: end;
}
.contact-band .section-overline {
  color: #ffd4c4;
}
.contact-band h2 {
  margin: 22px 0 0;
  font-size: clamp(38px, 5vw, 66px);
  line-height: 0.98;
  letter-spacing: -3px;
}
.footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 31px 0;
  color: #82938a;
  font-size: 10px;
}
.footer .brand {
  color: #18352d;
  font-size: 16px;
}
.footer .brand-mark {
  transform: scale(0.8);
  transform-origin: right center;
}
@media (max-width: 800px) {
  .container {
    width: min(100% - 40px, 560px);
  }
  .nav {
    height: 74px;
  }
  .nav-links {
    display: none;
  }
  .hero {
    min-height: 0;
    padding-bottom: 45px;
  }
  .hero-grid {
    display: block;
    padding-top: 65px;
  }
  .hero h1 {
    letter-spacing: -2.5px;
  }
  .trust-row {
    margin-top: 55px;
    flex-wrap: wrap;
    gap: 12px;
  }
  .hero-visual {
    margin: 82px 8px 0;
  }
  .dashboard-card {
    transform: rotate(1deg);
  }
  .floating-note {
    left: -12px;
    bottom: -31px;
  }
  .hero-footer {
    padding-top: 70px;
  }
  .intro-band {
    padding: 80px 0;
  }
  .intro-grid,
  .section-heading,
  .solution-layout {
    display: block;
  }
  .intro-grid h2 {
    margin: 25px 0;
  }
  .section-heading > p {
    margin-top: 25px;
  }
  .solution-layout {
    margin-top: 45px;
  }
  .solution-detail {
    margin-top: 45px;
    padding: 30px;
  }
  .solutions-section {
    padding-bottom: 85px;
  }
  .contact-content {
    display: block;
  }
  .contact-band .button {
    margin-top: 35px;
  }
  .footer {
    align-items: flex-start;
    flex-direction: column;
    gap: 17px;
  }
}
@media (max-width: 420px) {
  .nav-cta {
    font-size: 0;
  }
  .nav-cta .v-icon {
    font-size: 20px !important;
  }
  .hero-actions {
    align-items: flex-start;
    flex-direction: column;
    gap: 22px;
  }
  .dashboard-bottom strong {
    font-size: 17px;
  }
  .map-panel {
    height: 195px;
  }
  .solution-detail h3 {
    font-size: 27px;
  }
}
.solution-link {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 17px;
  padding: 22px 0;
  border-bottom: 1px solid #cdd6ca;
  color: #18352d;
  font:
    600 16px "Manrope",
    sans-serif;
  text-decoration: none;
}
.solution-link span {
  color: #e16b4c;
  font:
    10px "DM Mono",
    monospace;
}
.solution-link .v-icon {
  margin-left: auto;
}
.solution-details {
  display: grid;
  gap: 18px;
}
.response-detail {
  background: #e9ded0;
}
@media (max-width: 800px) {
  .solution-details {
    margin-top: 45px;
  }
}
</style>
