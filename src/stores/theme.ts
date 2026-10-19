import { defineStore } from 'pinia'
import { ref } from 'vue'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'
import vuetify from '@/plugins/vuetify'

export type NorthstarTheme = 'light' | 'dark'

const storageKey = 'northstar-theme'
const userStorageKey = (userId: string) => `${storageKey}:${userId}`
const isTheme = (value: unknown): value is NorthstarTheme => value === 'light' || value === 'dark'

function preferredTheme (): NorthstarTheme {
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

export const useThemeStore = defineStore('theme', () => {
  const current = ref<NorthstarTheme>(isTheme(localStorage.getItem(storageKey))
    ? localStorage.getItem(storageKey) as NorthstarTheme
    : preferredTheme())
  const persistenceError = ref('')
  let persistenceQueue = Promise.resolve()
  let activeUserId = ''

  function apply (value: NorthstarTheme) {
    current.value = value
    document.documentElement.dataset.northstarTheme = value
    document.documentElement.style.colorScheme = value
    vuetify.theme.global.name.value = value === 'dark' ? 'northstarDark' : 'northstarLight'
  }

  function saveLocally (value: NorthstarTheme, userId = activeUserId) {
    localStorage.setItem(storageKey, value)
    if (userId) localStorage.setItem(userStorageKey(userId), value)
  }

  async function persistForUser (value: NorthstarTheme, userId: string) {
    const client = supabase
    if (!isSupabaseConfigured || !client) return

    persistenceQueue = persistenceQueue.then(async () => {
      const { data, error: readError } = await client
        .from('user_preferences')
        .select('preferences')
        .eq('user_id', userId)
        .maybeSingle()
      if (readError) throw readError

      const existing = data?.preferences && typeof data.preferences === 'object'
        ? data.preferences as Record<string, unknown>
        : {}
      const { error } = await client.from('user_preferences').upsert({
        user_id: userId,
        preferences: { ...existing, theme: value },
      })
      if (error) throw error
      persistenceError.value = ''
      saveLocally(value, userId)
    }).catch(error => {
      persistenceError.value = `Theme is saved on this device, but could not be saved to your account: ${error.message}`
      console.error(persistenceError.value, error)
    })

    await persistenceQueue
  }

  function setTheme (value: NorthstarTheme, userId = activeUserId, persist = true) {
    activeUserId = userId
    apply(value)
    saveLocally(value, userId)
    if (persist && userId) void persistForUser(value, userId)
  }

  async function loadForUser (userId: string) {
    activeUserId = userId
    const localValue = userId
      ? localStorage.getItem(userStorageKey(userId))
      : localStorage.getItem(storageKey)
    if (isTheme(localValue)) apply(localValue)

    if (!userId || !isSupabaseConfigured || !supabase) return

    const { data, error } = await supabase
      .from('user_preferences')
      .select('preferences')
      .eq('user_id', userId)
      .maybeSingle()
    if (activeUserId !== userId) return
    if (error) {
      persistenceError.value = `Could not load your saved appearance preference: ${error.message}`
      console.error(persistenceError.value, error)
      return
    }

    const savedTheme = data?.preferences && typeof data.preferences === 'object'
      ? (data.preferences as Record<string, unknown>).theme
      : undefined
    if (isTheme(savedTheme)) {
      apply(savedTheme)
      saveLocally(savedTheme, userId)
    }
  }

  return { current, persistenceError, setTheme, loadForUser }
})
