import { createClient } from '@supabase/supabase-js'

const configuredSupabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim()
let supabaseUrl = configuredSupabaseUrl
let supabaseUrlError = ''

if (supabaseUrl) {
  try {
    const url = new URL(supabaseUrl)
    if (url.pathname === '/rest/v1' || url.pathname === '/rest/v1/') {
      url.pathname = '/'
      console.warn('Northstar Supabase URL included the REST API path; using the project root.')
    }
    if (
      !['http:', 'https:'].includes(url.protocol)
      || url.username
      || url.password
      || url.search
      || url.hash
      || (url.pathname !== '/' && url.pathname !== '')
    ) {
      throw new Error('invalid Supabase project URL')
    }
    supabaseUrl = url.origin
  } catch {
    supabaseUrl = undefined
    supabaseUrlError = 'VITE_SUPABASE_URL must be a valid project URL without an API path.'
  }
}

const supabaseKey = (
  import.meta.env.VITE_SUPABASE_ANON_KEY
    || import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
)?.trim()

const missingSupabaseVariables = [
  !supabaseUrl && 'VITE_SUPABASE_URL',
  !supabaseKey && 'VITE_SUPABASE_ANON_KEY or VITE_SUPABASE_PUBLISHABLE_KEY',
].filter(Boolean)

export const supabaseConfigurationError = [
  ...missingSupabaseVariables.map(variable => `Missing ${variable}.`),
  supabaseUrlError,
].filter(Boolean).join(' ')
export const isSupabaseConfigured = supabaseConfigurationError === ''
export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseKey, {
      auth: {
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: true,
      },
    })
  : null
