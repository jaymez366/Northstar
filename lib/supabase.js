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

export async function uploadPrivateMessageObject (path, file, onProgress = () => {}, signal) {
  if (!supabase || !isSupabaseConfigured || !supabaseUrl || !supabaseKey) {
    throw new Error('Private message uploads require a configured Supabase connection.')
  }
  const { data, error } = await supabase.auth.getSession()
  if (error || !data.session?.access_token) {
    throw new Error(error?.message || 'Sign in again before uploading an attachment.')
  }

  const encodedPath = path.split('/').map(segment => encodeURIComponent(segment)).join('/')
  const request = new XMLHttpRequest()
  const endpoint = `${supabaseUrl}/storage/v1/object/northstar-message-attachments/${encodedPath}`

  return new Promise((resolve, reject) => {
    const cleanup = () => signal?.removeEventListener('abort', abort)
    const abort = () => request.abort()
    request.open('POST', endpoint)
    request.setRequestHeader('apikey', supabaseKey)
    request.setRequestHeader('Authorization', `Bearer ${data.session.access_token}`)
    request.setRequestHeader('Content-Type', file.type)
    request.setRequestHeader('x-upsert', 'false')
    request.upload.onprogress = event => {
      if (event.lengthComputable) onProgress(Math.round((event.loaded / event.total) * 100))
    }
    request.onerror = () => { cleanup(); reject(new Error('The upload failed because the network connection was interrupted.')) }
    request.onabort = () => { cleanup(); reject(new DOMException('Upload cancelled.', 'AbortError')) }
    request.onload = () => {
      cleanup()
      if (request.status >= 200 && request.status < 300) {
        onProgress(100)
        resolve()
        return
      }
      let message = `Storage upload failed (${request.status}).`
      try {
        const body = JSON.parse(request.responseText)
        if (typeof body.message === 'string') message = body.message
      } catch {
        // Keep the generic status message when Storage returns a non-JSON error.
      }
      if ((request.status === 400 || request.status === 409) && /already exists|resource exists/i.test(message)) {
        // Retry the metadata RPC against the immutable object already uploaded at this idempotency path.
        resolve()
        return
      }
      reject(new Error(message))
    }
    if (signal?.aborted) {
      abort()
      return
    }
    signal?.addEventListener('abort', abort, { once: true })
    request.send(file)
  })
}
