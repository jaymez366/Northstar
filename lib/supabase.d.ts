import type { SupabaseClient } from '@supabase/supabase-js'

export const isSupabaseConfigured: boolean
export const supabaseConfigurationError: string
export const supabase: SupabaseClient | null
