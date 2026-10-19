/**
 * plugins/vuetify.ts
 *
 * Framework documentation: https://vuetifyjs.com`
 */

// Composables
import { createVuetify } from 'vuetify'
// Styles
import '@mdi/font/css/materialdesignicons.css'
import 'vuetify/styles'

// https://vuetifyjs.com/en/introduction/why-vuetify/#feature-guides
export default createVuetify({
  theme: {
    defaultTheme: 'northstarLight',
    themes: {
      northstarLight: {
        dark: false,
        colors: {
          background: '#f3f6fa',
          surface: '#ffffff',
          primary: '#2563eb',
          secondary: '#0f766e',
          success: '#15803d',
          warning: '#a16207',
          error: '#b42318',
          info: '#2563eb',
        },
      },
      northstarDark: {
        dark: true,
        colors: {
          background: '#111827',
          surface: '#1c2738',
          primary: '#75a7ff',
          secondary: '#55d6be',
          success: '#86efac',
          warning: '#fcd34d',
          error: '#fca5a5',
          info: '#7dd3fc',
        },
      },
    },
  },
})
