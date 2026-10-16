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

// Components
import App from './App.vue'

// Styles
import 'unfonts.css'
import 'virtual:uno.css'
import './styles/main.scss'

const app = createApp(App)

registerPlugins(app)

const auth = useAuthStore()
void auth.initialize().then(() => {
  if ('serviceWorker' in navigator) {
    void navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(error => {
      console.error('Northstar service worker registration failed', error)
    })
  }
  app.mount('#app')
})
