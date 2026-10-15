import { createClient } from 'npm:@supabase/supabase-js@2'

const allowedOrigins = new Set(
  (Deno.env.get('ALLOWED_ORIGINS')
    ?? 'https://northstar-1k1.pages.dev,http://localhost:3000,http://127.0.0.1:3000')
    .split(',')
    .map(origin => origin.trim())
    .filter(Boolean),
)

const corsHeaders = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Vary': 'Origin',
}

function response (body: Record<string, unknown>, status: number, origin: string | null) {
  const headers = new Headers(corsHeaders)
  if (origin && allowedOrigins.has(origin)) {
    headers.set('Access-Control-Allow-Origin', origin)
  }
  return Response.json(body, { status, headers })
}

function validEmail (email: string) {
  const [localPart, domain, ...extraParts] = email.split('@')
  return email.length <= 254
    && Boolean(localPart)
    && localPart.length <= 64
    && /^[^\s@]+$/.test(localPart)
    && Boolean(domain)
    && /^[a-z0-9.-]+$/.test(domain)
    && domain.includes('.')
    && !domain.startsWith('.')
    && !domain.endsWith('.')
    && !domain.includes('..')
    && extraParts.length === 0
}

function validRedirect (redirect: string) {
  return [
    'https://northstar-1k1.pages.dev/auth/callback',
    'http://localhost:3000/auth/callback',
    'http://127.0.0.1:3000/auth/callback',
  ].includes(redirect)
}

function optionsResponse (origin: string | null) {
  const headers = new Headers(corsHeaders)
  if (origin) {
    headers.set('Access-Control-Allow-Origin', origin)
  }
  return new Response(null, { status: 204, headers })
}

async function sendConfirmation (email: string, emailRedirectTo: string, origin: string | null) {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error('Confirmation resend function is missing required server configuration.')
    return response({ error: 'Confirmation email service is temporarily unavailable.' }, 503, origin)
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data: rateLimit, error: rateLimitError } = await adminClient
    .rpc('consume_confirmation_resend_limit', { p_email: email })
    .single()

  if (rateLimitError || !rateLimit) {
    console.error('Could not check confirmation resend limit.', rateLimitError)
    return response({ error: 'Confirmation email service is temporarily unavailable.' }, 503, origin)
  }
  if (!rateLimit.eligible || !rateLimit.allowed) {
    return response({ status: 'accepted' }, 200, origin)
  }

  const publicClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { error: resendError } = await publicClient.auth.resend({
    type: 'signup',
    email,
    options: { emailRedirectTo },
  })

  if (resendError) {
    const safeNoop = /already confirmed|user not found|rate limit/i.test(resendError.message)
    if (!safeNoop) {
      console.error('Supabase confirmation email request failed.', {
        status: resendError.status,
        code: resendError.code ?? 'unknown',
      })
      return response({ error: 'Confirmation email service is temporarily unavailable.' }, 503, origin)
    }
  }

  return response({ status: 'accepted' }, 200, origin)
}

Deno.serve(async request => {
  const origin = request.headers.get('origin')

  if (request.method === 'OPTIONS') {
    return origin && !allowedOrigins.has(origin)
      ? response({ error: 'Origin is not allowed.' }, 403, null)
      : optionsResponse(origin)
  }
  if (request.method !== 'POST') {
    return response({ error: 'Method not allowed.' }, 405, origin)
  }
  if (origin && !allowedOrigins.has(origin)) {
    return response({ error: 'Origin is not allowed.' }, 403, null)
  }

  let body: { email?: unknown, emailRedirectTo?: unknown }
  try {
    body = await request.json()
  } catch {
    return response({ error: 'Invalid request.' }, 400, origin)
  }

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''
  const emailRedirectTo = typeof body.emailRedirectTo === 'string' ? body.emailRedirectTo : ''
  if (!validEmail(email) || !validRedirect(emailRedirectTo)) {
    return response({ error: 'Enter a valid Northstar account email.' }, 400, origin)
  }

  return sendConfirmation(email, emailRedirectTo, origin)
})
