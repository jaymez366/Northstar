import { createClient } from 'npm:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

type WebhookBody = {
  type?: unknown
  table?: unknown
  schema?: unknown
  record?: { id?: unknown, user_id?: unknown }
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function response (body: Record<string, unknown>, status = 200) {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } })
}

function matchesSecret (provided: string | null, expected: string) {
  if (!provided || provided.length !== expected.length) return false
  let mismatch = 0
  for (let index = 0; index < expected.length; index += 1) {
    mismatch |= provided.charCodeAt(index) ^ expected.charCodeAt(index)
  }
  return mismatch === 0
}

function preferenceAllows (preferences: unknown, notificationType: string) {
  if (!preferences || typeof preferences !== 'object') return true
  const saved = preferences as Record<string, unknown>
  if (notificationType === 'message') return saved.messages !== false
  if (notificationType === 'event') return saved.events !== false
  if (notificationType === 'announcement' || notificationType === 'resource') return saved.announcements !== false
  return true
}

Deno.serve(async request => {
  if (request.method !== 'POST') return response({ error: 'Method not allowed.' }, 405)

  const webhookSecret = Deno.env.get('NORTHSTAR_NOTIFICATION_WEBHOOK_SECRET')
  const providedSecret = request.headers.get('x-northstar-webhook-secret')
  if (!webhookSecret || webhookSecret.length < 32) {
    console.error('Northstar notification webhook secret must contain at least 32 characters.')
    return response({ error: 'Push delivery is not configured.' }, 503)
  }
  if (!matchesSecret(providedSecret, webhookSecret)) {
    return response({ error: 'Unauthorized webhook.' }, 401)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY')
  const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY')
  const vapidSubject = Deno.env.get('VAPID_SUBJECT')
  if (!supabaseUrl || !serviceRoleKey || !vapidPublicKey || !vapidPrivateKey || !vapidSubject) {
    console.error('Northstar push delivery is missing server configuration.')
    return response({ error: 'Push delivery is not configured.' }, 503)
  }

  let body: WebhookBody
  try {
    body = await request.json()
  } catch {
    return response({ error: 'Invalid webhook payload.' }, 400)
  }
  if (body.type !== 'INSERT' || body.schema !== 'public' || body.table !== 'notifications') {
    return response({ ignored: true })
  }

  const record = body.record
  if (typeof record?.id !== 'string' || !uuidPattern.test(record.id)) {
    return response({ error: 'Notification ID is invalid.' }, 400)
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data: notification, error: notificationError } = await admin
    .from('notifications')
    .select('id,user_id,title,message,notification_type,link_to')
    .eq('id', record.id)
    .maybeSingle()
  if (notificationError || !notification) {
    console.error('Could not load inserted Northstar notification.', notificationError)
    return response({ ignored: true })
  }

  const { data: preferenceRow } = await admin
    .from('user_preferences')
    .select('preferences')
    .eq('user_id', notification.user_id)
    .maybeSingle()
  if (!preferenceAllows(preferenceRow?.preferences, notification.notification_type)) {
    return response({ skipped: 'notification preference disabled' })
  }

  webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey)
  const { data: subscriptions, error: subscriptionError } = await admin
    .from('northstar_push_subscriptions')
    .select('endpoint,subscription')
    .eq('user_id', notification.user_id)
  if (subscriptionError) {
    console.error('Could not load Northstar device subscriptions.', subscriptionError)
    return response({ error: 'Could not load device subscriptions.' }, 503)
  }

  const url = typeof notification.link_to === 'string'
    && notification.link_to.startsWith('/')
    && !notification.link_to.startsWith('//')
    ? notification.link_to
    : '/notifications'
  const payload = JSON.stringify({
    title: notification.title,
    body: notification.message,
    url,
    tag: `northstar-${notification.id}`,
  })

  let retryNeeded = false
  for (const subscriptionRow of subscriptions ?? []) {
    const { error: claimError } = await admin.from('northstar_push_deliveries').insert({
      notification_id: notification.id,
      endpoint: subscriptionRow.endpoint,
      status: 'claimed',
    })
    if (claimError?.code === '23505') {
      const { data: reclaimed, error: reclaimError } = await admin.from('northstar_push_deliveries')
        .update({ status: 'claimed', attempted_at: new Date().toISOString() })
        .eq('notification_id', notification.id)
        .eq('endpoint', subscriptionRow.endpoint)
        .eq('status', 'failed')
        .select('notification_id')
        .maybeSingle()
      if (reclaimError) {
        console.error('Could not retry failed Northstar push delivery.', reclaimError)
        retryNeeded = true
        continue
      }
      if (!reclaimed) continue
    }
    if (claimError && claimError.code !== '23505') {
      retryNeeded = true
      console.error('Could not claim Northstar push delivery.', claimError)
      continue
    }

    try {
      await webpush.sendNotification(subscriptionRow.subscription, payload)
      const { error: sentUpdateError } = await admin.from('northstar_push_deliveries')
        .update({ status: 'sent', attempted_at: new Date().toISOString() })
        .eq('notification_id', notification.id)
        .eq('endpoint', subscriptionRow.endpoint)
      if (sentUpdateError) {
        console.error('Could not record successful Northstar push delivery.', sentUpdateError)
        retryNeeded = true
      }
    } catch (error) {
      const statusCode = typeof error === 'object' && error !== null && 'statusCode' in error
        ? Number((error as { statusCode: unknown }).statusCode)
        : 0
      const { error: failedUpdateError } = await admin.from('northstar_push_deliveries')
        .update({ status: 'failed', attempted_at: new Date().toISOString() })
        .eq('notification_id', notification.id)
        .eq('endpoint', subscriptionRow.endpoint)
      if (failedUpdateError) retryNeeded = true
      if (statusCode === 404 || statusCode === 410) {
        const { error: expiredDeleteError } = await admin.from('northstar_push_subscriptions').delete().eq('endpoint', subscriptionRow.endpoint)
        if (expiredDeleteError) {
          console.error('Could not remove expired Northstar push subscription.', expiredDeleteError)
          retryNeeded = true
        }
      } else {
        console.error('Northstar push delivery failed.', { statusCode })
        retryNeeded = true
      }
    }
  }

  // The in-app row remains available even if a device delivery fails.
  return retryNeeded
    ? response({ error: 'One or more device deliveries need retry.' }, 503)
    : response({ delivered: true })
})
