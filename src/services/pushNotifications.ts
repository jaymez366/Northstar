import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'
import { useAuthStore } from '@/stores/auth'

const isUuid = (value: string | null | undefined): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)

function getApplicationServerKey (): Uint8Array<ArrayBuffer> {
  const encodedKey = import.meta.env.VITE_VAPID_PUBLIC_KEY?.trim()
  if (!encodedKey) throw new Error('Device notifications are not configured. Ask your Northstar administrator to configure the push public key.')
  const base64 = encodedKey.replace(/-/g, '+').replace(/_/g, '/')
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=')
  const raw = atob(padded)
  const key = new Uint8Array(new ArrayBuffer(raw.length))
  for (let index = 0; index < raw.length; index += 1) {
    key[index] = raw.charCodeAt(index)
  }
  return key
}

function getSupportError () {
  if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
    return 'This browser or device does not support web push notifications.'
  }
  return ''
}

export async function hasDevicePushSubscription () {
  if (getSupportError()) return false
  const registration = await navigator.serviceWorker.ready
  return Boolean(await registration.pushManager.getSubscription())
}

export async function enableDevicePush () {
  const auth = useAuthStore()
  if (!isSupabaseConfigured || !supabase || !isUuid(auth.userId)) {
    return { success: false, message: 'Sign in to Northstar before enabling device notifications.' }
  }
  const unsupported = getSupportError()
  if (unsupported) return { success: false, message: unsupported }

  let applicationServerKey: Uint8Array<ArrayBuffer>
  try {
    applicationServerKey = getApplicationServerKey()
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : 'The push public key is unavailable.' }
  }

  let permission = Notification.permission
  if (permission === 'default') permission = await Notification.requestPermission()
  if (permission !== 'granted') {
    return { success: false, message: permission === 'denied'
      ? 'Notifications are blocked for this site in your browser settings.'
      : 'Notification permission was not granted.' }
  }

  try {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
      ?? await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey })
    const endpoint = subscription.endpoint
    const { error } = await supabase.from('northstar_push_subscriptions').upsert({
      user_id: auth.userId,
      endpoint,
      subscription: subscription.toJSON(),
      updated_at: new Date().toISOString(),
    }, { onConflict: 'endpoint' })
    if (error) {
      await subscription.unsubscribe()
      return { success: false, message: `The device subscription could not be saved: ${error.message}` }
    }
    return { success: true, message: 'Device notifications are enabled on this device.' }
  } catch (error) {
    console.error('Could not enable Northstar device notifications', error)
    return { success: false, message: 'Device notifications could not be enabled. Please try again.' }
  }
}

export async function disableDevicePush () {
  const auth = useAuthStore()
  if (!isSupabaseConfigured || !supabase || !isUuid(auth.userId)) {
    return { success: false, message: 'Sign in to Northstar before changing device notifications.' }
  }
  const unsupported = getSupportError()
  if (unsupported) return { success: false, message: unsupported }

  try {
    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.getSubscription()
    if (subscription) {
      const { error } = await supabase.from('northstar_push_subscriptions')
        .delete()
        .eq('user_id', auth.userId)
        .eq('endpoint', subscription.endpoint)
      if (error) return { success: false, message: `The device subscription could not be removed: ${error.message}` }
      await subscription.unsubscribe()
    }
    return { success: true, message: 'Device notifications are disabled on this device.' }
  } catch (error) {
    console.error('Could not disable Northstar device notifications', error)
    return { success: false, message: 'Device notifications could not be disabled. Please try again.' }
  }
}
