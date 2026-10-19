<script setup lang="ts">
  import { useAuthStore } from '@/stores/auth'
  import { useThemeStore, type NorthstarTheme } from '@/stores/theme'

  const auth = useAuthStore()
  const appearance = useThemeStore()

  function chooseTheme (theme: NorthstarTheme) {
    appearance.setTheme(theme, auth.userId)
  }
</script>

<template>
  <div class="theme-switcher" role="group" aria-label="Color theme">
    <button
      type="button"
      :aria-pressed="appearance.current === 'light'"
      aria-label="Use light mode"
      title="Light mode"
      @click="chooseTheme('light')"
    >
      <v-icon icon="mdi-white-balance-sunny" size="17" />
      <span>Light</span>
    </button>
    <button
      type="button"
      :aria-pressed="appearance.current === 'dark'"
      aria-label="Use dark mode"
      title="Dark mode"
      @click="chooseTheme('dark')"
    >
      <v-icon icon="mdi-weather-night" size="17" />
      <span>Dark</span>
    </button>
  </div>
</template>

<style scoped>
.theme-switcher { display: inline-flex; align-items: center; gap: 3px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); border-radius: 999px; padding: 3px; background: var(--ns-bg-ffffff, #fff); }
.theme-switcher button { display: inline-flex; min-height: 30px; align-items: center; justify-content: center; gap: 5px; border: 0; border-radius: 999px; padding: 0 9px; background: transparent; color: var(--ns-text-52645a, #52645a); cursor: pointer; font: 600 10px "Manrope", sans-serif; }
.theme-switcher button[aria-pressed="true"] { background: var(--ns-bg-eaf3bd, #eaf3bd); color: var(--ns-text-18352d, #18352d); }
.theme-switcher button:focus-visible { outline: 2px solid var(--ns-border-2563eb, #2563eb); outline-offset: 2px; }
@media (max-width: 680px) { .theme-switcher span { display: none; } .theme-switcher button { width: 30px; padding: 0; } }
</style>
