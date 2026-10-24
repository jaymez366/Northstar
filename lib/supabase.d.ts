import type { SupabaseClient } from '@supabase/supabase-js'

export declare const supabase: SupabaseClient | null
export declare const isSupabaseConfigured: boolean
export declare const supabaseConfigurationError: string
export declare function uploadPrivateMessageObject(
  path: string,
  file: File,
  onProgress?: (percent: number) => void,
  signal?: AbortSignal,
): Promise<void>
