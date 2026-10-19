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
          background: '#f3f5ef',
          surface: '#ffffff',
          primary: '#2563eb',
          secondary: '#526c5c',
          success: '#4b8058',
          warning: '#94651e',
          error: '#a34c39',
          info: '#2563eb',
        },
      },
      northstarDark: {
        dark: true,
        colors: {
          background: '#111827',
          surface: '#1e293b',
          primary: '#60a5fa',
          secondary: '#5eead4',
          success: '#86efac',
          warning: '#fcd34d',
          error: '#fca5a5',
          info: '#7dd3fc',
        },
      },
    },
  },
})
