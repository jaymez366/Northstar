<script setup lang="ts">
  import { useAuthStore } from '@/stores/auth'
  import { useThemeStore } from '@/stores/theme'

  const auth = useAuthStore()
  const appearance = useThemeStore()

  function toggleTheme () {
    appearance.setTheme(appearance.current === 'light' ? 'dark' : 'light', auth.userId)
  }
</script>

<template>
  <div class="theme-switcher">
    <button
      class="theme-switcher-button"
      type="button"
      :aria-label="`Switch to ${appearance.current === 'light' ? 'Dark' : 'Light'} Mode`"
      :aria-pressed="appearance.current === 'dark'"
      :title="`Switch to ${appearance.current === 'light' ? 'Dark' : 'Light'} Mode`"
      @click="toggleTheme"
    >
      <v-icon :icon="appearance.current === 'light' ? 'mdi-white-balance-sunny' : 'mdi-weather-night'" size="18" />
      <span>{{ appearance.current === 'light' ? 'Light mode' : 'Dark mode' }}</span>
      <v-icon class="theme-switcher-arrow" icon="mdi-chevron-down" size="15" />
    </button>
  </div>
</template>

<style scoped>
.theme-switcher { display: inline-flex; flex: 0 0 auto; }
.theme-switcher-button { display: inline-flex; min-width: 126px; min-height: 38px; align-items: center; justify-content: center; gap: 7px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); border-radius: 999px; padding: 0 12px; background: var(--ns-bg-ffffff, #fff); color: var(--ns-text-18352d, #18352d); cursor: pointer; font: 700 10px "Manrope", sans-serif; white-space: nowrap; }
.theme-switcher-button:hover { border-color: var(--ns-border-2563eb, #2563eb); }
.theme-switcher-button:focus-visible { outline: 2px solid var(--ns-primary); outline-offset: 2px; }
.theme-switcher-button .v-icon:first-child { color: var(--ns-primary); }
.theme-switcher-arrow { margin-left: auto; color: var(--ns-text-secondary); }
@media (max-width: 680px) { .theme-switcher-button { min-width: 116px; min-height: 36px; padding: 0 10px; } }
</style>
