import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim()
const supabaseKey = (
  import.meta.env.VITE_SUPABASE_ANON_KEY
    || import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
)?.trim()

const missingSupabaseVariables = [
  !supabaseUrl && 'VITE_SUPABASE_URL',
  !supabaseKey && 'VITE_SUPABASE_ANON_KEY or VITE_SUPABASE_PUBLISHABLE_KEY',
].filter(Boolean)

export const supabaseConfigurationError = missingSupabaseVariables.length > 0
  ? `Missing ${missingSupabaseVariables.join(' and ')}.`
  : ''
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
