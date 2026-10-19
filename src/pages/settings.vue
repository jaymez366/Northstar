<script setup lang="ts">
  import { onMounted, reactive, ref, watch } from 'vue'
  import { useI18n } from 'vue-i18n'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'
  import { useThemeStore, type NorthstarTheme } from '@/stores/theme'
  import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

  const auth = useAuthStore()
  const appearance = useThemeStore()
  const router = useRouter()
  const i18n = useI18n()
  const saved = ref(false)
  const saving = ref(false)
  const settingsError = ref('')
  const defaults = {
    announcements: true,
    messages: true,
    events: false,
    compact: false,
    language: 'en' as 'en' | 'ja',
  }
  const preferences = reactive({ ...defaults })

  async function loadSettings () {
    if (!isSupabaseConfigured || !supabase) {
      settingsError.value = 'Northstar Supabase is not configured, so account settings cannot be loaded.'
      return
    }
    const { data, error } = await supabase
      .from('user_preferences')
      .select('preferences')
      .eq('user_id', auth.userId)
      .maybeSingle()
    if (error) {
      settingsError.value = `Could not load your account settings: ${error.message}`
      console.error(settingsError.value, error)
      return
    }
    if (data?.preferences && typeof data.preferences === 'object') {
      Object.assign(preferences, data.preferences)
      const savedTheme = (data.preferences as Record<string, unknown>).theme
      if (savedTheme === 'light' || savedTheme === 'dark') {
        appearance.setTheme(savedTheme as NorthstarTheme, auth.userId, false)
      }
    }
    i18n.locale.value = preferences.language
  }

  watch(() => preferences.compact, compact => {
    document.documentElement.classList.toggle('compact-workspace', compact)
  }, { immediate: true })

  async function saveSettings () {
    if (!isSupabaseConfigured || !supabase) {
      settingsError.value = 'Saving settings requires a configured Northstar Supabase connection.'
      return
    }
    settingsError.value = ''
    saving.value = true
    const { error } = await supabase.from('user_preferences').upsert({
      user_id: auth.userId,
      preferences: { ...preferences, theme: appearance.current },
    })
    saving.value = false
    if (error) {
      settingsError.value = `Could not save your account settings: ${error.message}`
      console.error(settingsError.value, error)
      return
    }
    i18n.locale.value = preferences.language
    saved.value = true
    window.setTimeout(() => {
      saved.value = false
    }, 2500)
  }

  function logout () {
    void auth.logout().then(signedOut => {
      if (signedOut) router.push('/login')
    })
  }

  onMounted(() => {
    void loadSettings()
  })
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">MAKE IT YOURS</p><h1>Settings</h1><p>Manage your account, notifications, and workspace preferences.</p></div></header>
    <p v-if="saved" class="saved-message" role="status"><v-icon icon="mdi-check-circle-outline" size="17" /> Settings saved to your account.</p>
    <p v-if="settingsError" class="settings-error" role="alert">{{ settingsError }}</p>

    <div class="settings-layout">
      <nav class="settings-index"><a href="#account">Account</a><a href="#notifications">Notifications</a><a href="#security">Security</a><a href="#appearance">Appearance</a><a href="#language">Language</a></nav>

      <div class="settings-sections">
        <section id="account" class="settings-card surface-card"><h2>Account</h2><p>Manage your Northstar account details.</p><router-link to="/profile">Edit your profile <v-icon icon="mdi-arrow-right" size="15" /></router-link><div class="settings-row"><span><strong>Email address</strong><small>{{ auth.userEmail }}</small></span><v-icon icon="mdi-check-circle-outline" size="19" /></div></section>
        <section id="notifications" class="settings-card surface-card"><h2>Notifications</h2><p>Choose the updates you want to hear about.</p><label class="setting-toggle"><span><strong>Announcements</strong><small>Company news and important updates</small></span><input v-model="preferences.announcements" type="checkbox"></label><label class="setting-toggle"><span><strong>Direct messages</strong><small>When a colleague sends you a message</small></span><input v-model="preferences.messages" type="checkbox"></label><label class="setting-toggle"><span><strong>Events and reminders</strong><small>Invitations and upcoming event reminders</small></span><input v-model="preferences.events" type="checkbox"></label></section>
        <section id="security" class="settings-card surface-card"><h2>Security</h2><p>Keep your account protected.</p><div class="settings-row"><span><strong>Password</strong><small>Update your password through your account provider.</small></span><v-icon icon="mdi-lock-outline" size="19" /></div><div class="settings-row"><span><strong>Active session</strong><small>This device · Signed in as {{ auth.userEmail }}</small></span><span class="secure-label">SECURE</span></div></section>
        <section id="appearance" class="settings-card surface-card"><h2>Appearance</h2><p>Choose the Northstar color theme. Your selection applies immediately and is saved with your account preferences.</p><div class="appearance-theme-options"><button type="button" :aria-pressed="appearance.current === 'light'" @click="appearance.setTheme('light', auth.userId)"><v-icon icon="mdi-white-balance-sunny" size="18" /><span><strong>Light mode</strong><small>Bright, clean surfaces</small></span><v-icon v-if="appearance.current === 'light'" icon="mdi-check-circle" size="18" /></button><button type="button" :aria-pressed="appearance.current === 'dark'" @click="appearance.setTheme('dark', auth.userId)"><v-icon icon="mdi-weather-night" size="18" /><span><strong>Dark mode</strong><small>Comfortable in dim environments</small></span><v-icon v-if="appearance.current === 'dark'" icon="mdi-check-circle" size="18" /></button></div><p v-if="appearance.persistenceError" class="settings-error" role="status">{{ appearance.persistenceError }}</p><label class="setting-toggle"><span><strong>Compact display</strong><small>Use tighter spacing across the workspace</small></span><input v-model="preferences.compact" type="checkbox"></label></section>
        <section id="language" class="settings-card surface-card"><h2>Language</h2><p>Choose your preferred display language.</p><select v-model="preferences.language" class="field-control"><option value="en">English</option><option value="ja">日本語</option></select></section>
        <section class="settings-card logout-card"><div><h2>Sign out</h2><p>End your current Northstar session on this device.</p></div><button class="secondary-action" @click="logout"><v-icon icon="mdi-logout" size="16" /> Sign out</button></section>
      </div>
    </div>

    <div class="save-settings"><button class="primary-action" :disabled="saving" @click="saveSettings"><v-icon icon="mdi-content-save-outline" size="16" /> {{ saving ? 'Saving…' : 'Save preferences' }}</button></div>
  </main>
</template>

<style scoped>
.saved-message { display: flex; align-items: center; gap: 8px; color: var(--ns-text-4b8058, #4b8058); font-size: 10px; }
.settings-error { color: var(--ns-text-a34c39, #a34c39); font-size: 10px; }
.settings-layout { display: grid; grid-template-columns: 170px minmax(0, 1fr); align-items: start; gap: 18px; }
.settings-index { position: sticky; top: 95px; display: grid; gap: 3px; padding: 8px 0; }
.settings-index a { padding: 9px; color: var(--ns-text-718178, #718178); text-decoration: none; font-size: 10px; }
.settings-index a:hover { background: var(--ns-bg-e9efe3, #e9efe3); color: var(--ns-text-18352d, #18352d); }
.settings-sections { display: grid; gap: 12px; }
.settings-card { padding: 18px 20px; scroll-margin-top: 95px; }
.settings-card h2 { margin: 0; color: var(--ns-text-18352d, #18352d); font-size: 13px; }
.settings-card > p, .logout-card p { margin: 5px 0 13px; color: var(--ns-text-829187, #829187); font-size: 9px; }
.settings-card > a { display: inline-flex; align-items: center; gap: 5px; margin: 0 0 8px; color: var(--ns-text-526c5c, #526c5c); text-decoration: none; font-size: 10px; }
.settings-row, .setting-toggle { display: flex; min-height: 48px; align-items: center; justify-content: space-between; gap: 14px; border-top: 1px solid var(--ns-border-edf0e9, #edf0e9); }
.settings-row > span:first-child, .setting-toggle > span { display: grid; gap: 4px; }
.settings-row strong, .setting-toggle strong { color: var(--ns-text-52645a, #52645a); font-size: 10px; }
.settings-row small, .setting-toggle small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.settings-row > .v-icon { color: var(--ns-text-789780, #789780); }
.setting-toggle input { accent-color: #526c5c; }
.appearance-theme-options { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; margin: 14px 0; }
.appearance-theme-options button { display: flex; min-height: 64px; align-items: center; gap: 10px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); padding: 10px 12px; background: var(--ns-bg-fff, #fff); color: var(--ns-text-52645a, #52645a); cursor: pointer; text-align: left; }
.appearance-theme-options button[aria-pressed="true"] { border-color: var(--ns-border-2563eb, #2563eb); background: var(--ns-bg-eff6ff, #eff6ff); color: var(--ns-text-18352d, #18352d); }
.appearance-theme-options button > span { display: grid; flex: 1; gap: 4px; }
.appearance-theme-options strong { font-size: 10px; }
.appearance-theme-options small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.appearance-theme-options button:focus-visible { outline: 2px solid var(--ns-border-2563eb, #2563eb); outline-offset: 2px; }
.secure-label { color: var(--ns-text-63866b, #63866b); font: 8px "DM Mono", monospace; letter-spacing: 1px; }
.settings-card .field-control { min-width: 200px; }
.logout-card { display: flex; align-items: center; justify-content: space-between; gap: 14px; border: 1px solid var(--ns-border-f0d9d0, #f0d9d0); padding: 16px 20px; background: var(--ns-bg-fffaf8, #fffaf8); }
.logout-card h2 { color: var(--ns-text-a34c39, #a34c39); }
.logout-card p { margin-bottom: 0; }
.save-settings { display: flex; justify-content: flex-end; margin-top: 15px; }
@media (max-width: 680px) { .settings-layout { grid-template-columns: 1fr; } .settings-index { position: static; grid-template-columns: repeat(3, 1fr); } .settings-index a { text-align: center; } .logout-card { align-items: flex-start; flex-direction: column; } .appearance-theme-options { grid-template-columns: 1fr; } }
</style>
