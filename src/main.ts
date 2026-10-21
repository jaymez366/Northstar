/**
 * main.ts
 *
 * Bootstraps Vuetify and other plugins then mounts the App`
 */

// Composables
import { createApp } from 'vue'

// Plugins
import { registerPlugins } from '@/plugins'
import { useAuthStore } from '@/stores/auth'
import { useThemeStore } from '@/stores/theme'

// Components
import App from './App.vue'

// Styles
import 'unfonts.css'
import 'virtual:uno.css'
import './styles/main.scss'

const app = createApp(App)

registerPlugins(app)

const auth = useAuthStore()
const appearance = useThemeStore()
appearance.initializeLocalTheme()
void (async () => {
  await auth.initialize()
  await appearance.loadForUser(auth.userId)
  app.mount('#app')
})()
