import type { User } from '@supabase/supabase-js'
import { defineStore } from 'pinia'
import { ref } from 'vue'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

const storageKey = 'northstar-authenticated'
const accountKey = 'northstar-account'

export type UserProfile = {
  firstName: string
  lastName: string
  jobTitle: string
  department: string
  departmentId: string
  phone: string
  photoUrl: string
  avatarPath: string
  role: 'employee' | 'manager' | 'admin'
  status: 'active' | 'inactive'
}

type LegacyAccount = {
  email: string
  password: string
  firstName?: string
  lastName?: string
  jobTitle?: string
  department?: string
  phone?: string
  photoUrl?: string
  role?: 'employee' | 'manager' | 'admin'
}

function emptyProfile (): UserProfile {
  return {
    firstName: '',
    lastName: '',
    jobTitle: '',
    department: '',
    departmentId: '',
    phone: '',
    photoUrl: '',
    avatarPath: '',
    role: 'employee',
    status: 'active',
  }
}

export const useAuthStore = defineStore('auth', () => {
  const isAuthenticated = ref(localStorage.getItem(storageKey) === 'true')
  const isAdmin = ref(localStorage.getItem('northstar-user-role') === 'admin')
  const userId = ref('')
  const userEmail = ref(localStorage.getItem('northstar-user-email') ?? '')
  const userFirstName = ref(localStorage.getItem('northstar-user-first-name') ?? '')
  const isPasswordRecovery = ref(false)
  const profile = ref<UserProfile>(readCachedProfile())
  const ready = ref(false)
  const errorMessage = ref('')
  let initialization: Promise<void> | null = null
  let authSubscription: { unsubscribe: () => void } | null = null

  async function initialize () {
    if (ready.value) {
      return
    }
    if (initialization) {
      return initialization
    }

    initialization = (async () => {
      if (isSupabaseConfigured && supabase) {
        const { data, error } = await supabase.auth.getSession()
        if (error) {
          errorMessage.value = `Could not restore your Supabase session: ${error.message}`
          console.error(errorMessage.value, error)
        } else if (data.session) {
          applySupabaseUser(data.session.user)
          isPasswordRecovery.value = window.location.hash.includes('type=recovery')
          await loadProfile(data.session.user.id)
        } else {
          clearAuthenticatedUser()
        }

        const { data: authState } = supabase.auth.onAuthStateChange((event, session) => {
          if (event === 'PASSWORD_RECOVERY') {
            isPasswordRecovery.value = true
          }
          if (session) {
            applySupabaseUser(session.user)
            if (['SIGNED_IN', 'TOKEN_REFRESHED', 'USER_UPDATED'].includes(event)) {
              window.setTimeout(() => {
                void loadProfile(session.user.id)
              }, 0)
            }
          } else {
            clearAuthenticatedUser()
          }
        })
        authSubscription = authState.subscription
      }
      ready.value = true
    })()

    return initialization
  }

  async function loadProfile (id: string) {
    if (!supabase) {
      return
    }
    const { data, error } = await supabase
      .from('profiles')
      .select('first_name,last_name,job_title,department_id,phone,avatar_url,role,status,departments(name)')
      .eq('id', id)
      .maybeSingle()

    if (error) {
      errorMessage.value = `Could not load your profile from Supabase: ${error.message}`
      console.error(errorMessage.value, error)
      return
    }

    if (!data) {
      errorMessage.value = 'Your Supabase account has no profile yet. Apply the profile trigger SQL in Supabase.'
      return
    }

    const department = Array.isArray(data.departments) ? data.departments[0] : data.departments
    profile.value = {
      firstName: data.first_name ?? '',
      lastName: data.last_name ?? '',
      jobTitle: data.job_title ?? '',
      department: department?.name ?? '',
      departmentId: data.department_id ?? '',
      phone: data.phone ?? '',
      photoUrl: '',
      avatarPath: data.avatar_url ?? '',
      role: data.role ?? 'employee',
      status: data.status ?? 'active',
    }
    let avatarLoadError = ''
    if (profile.value.avatarPath) {
      const { data: avatar, error: avatarError } = await supabase.storage
        .from('profile-avatars')
        .createSignedUrl(profile.value.avatarPath, 3600)
      if (avatarError) {
        avatarLoadError = `Could not load your profile photo: ${avatarError.message}`
        console.error(avatarLoadError, avatarError)
      } else {
        profile.value.photoUrl = avatar.signedUrl
      }
    }
    userFirstName.value = profile.value.firstName
    isAdmin.value = profile.value.role === 'admin'
    localStorage.setItem('northstar-user-first-name', userFirstName.value)
    localStorage.setItem('northstar-user-role', profile.value.role)
    localStorage.setItem('northstar-user-profile', JSON.stringify(profile.value))
    errorMessage.value = avatarLoadError
  }

  async function login (email: string, password: string) {
    errorMessage.value = ''

    if (isSupabaseConfigured && supabase) {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) {
        errorMessage.value = error.message
        return false
      }
      if (!data.user) {
        errorMessage.value = 'Supabase did not return a user after sign-in.'
        return false
      }

      applySupabaseUser(data.user)
      localStorage.removeItem(accountKey)
      await loadProfile(data.user.id)
      return true
    }

    const savedAccount = localStorage.getItem(accountKey)
    const account = savedAccount ? JSON.parse(savedAccount) as LegacyAccount : null
    const isDemoAccount = email === 'demo@northstar.com' && password === 'northstar123'
    const isSavedAccount = account?.email === email && account.password === password
    if (!isDemoAccount && !isSavedAccount) {
      return false
    }

    isAuthenticated.value = true
    isAdmin.value = account?.role === 'admin' || isDemoAccount
    userEmail.value = email
    profile.value = isSavedAccount && account
      ? profileFromLegacy(account)
      : { ...emptyProfile(), firstName: 'Demo', lastName: 'User', jobTitle: 'Workspace administrator', department: 'Operations', role: 'admin' }
    userFirstName.value = profile.value.firstName || email.split('@', 1)[0]
    saveLocalSession()
    return true
  }

  async function signup (email: string, password: string, fullName: string) {
    errorMessage.value = ''
    const nameParts = fullName.trim().split(/\s+/)
    const firstName = nameParts[0] ?? ''
    const lastName = nameParts.slice(1).join(' ')

    if (isSupabaseConfigured && supabase) {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: { data: { first_name: firstName, last_name: lastName } },
      })
      if (error) {
        errorMessage.value = error.message
        return { success: false, requiresEmailConfirmation: false }
      }

      localStorage.removeItem(accountKey)
      if (data.session && data.user) {
        applySupabaseUser(data.user)
        await loadProfile(data.user.id)
        return { success: true, requiresEmailConfirmation: false }
      }

      return { success: true, requiresEmailConfirmation: true }
    }

    const account: LegacyAccount = {
      email,
      password,
      firstName,
      lastName,
      role: 'employee',
    }
    localStorage.setItem(accountKey, JSON.stringify(account))
    isAuthenticated.value = true
    isAdmin.value = false
    userEmail.value = email
    profile.value = profileFromLegacy(account)
    userFirstName.value = firstName
    saveLocalSession()
    return { success: true, requiresEmailConfirmation: false }
  }

  async function resetPassword (email: string) {
    errorMessage.value = ''
    if (!isSupabaseConfigured || !supabase) {
      errorMessage.value = 'Password reset requires Supabase. Configure your Supabase environment variables first.'
      return false
    }
    const redirectTo = `${window.location.origin}/reset-password`
    const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo })
    if (error) {
      errorMessage.value = error.message
      return false
    }
    return true
  }

  async function updatePassword (password: string) {
    errorMessage.value = ''
    if (!isSupabaseConfigured || !supabase) {
      errorMessage.value = 'Password updates require Supabase. Configure your Supabase environment variables first.'
      return false
    }
    const { error } = await supabase.auth.updateUser({ password })
    if (error) {
      errorMessage.value = `Could not update your password: ${error.message}`
      console.error(errorMessage.value, error)
      return false
    }
    isPasswordRecovery.value = false
    return true
  }

  async function saveProfile (updates: Partial<UserProfile>) {
    errorMessage.value = ''
    if (isSupabaseConfigured && supabase && userId.value) {
      const { error } = await supabase.from('profiles').update({
        first_name: updates.firstName,
        last_name: updates.lastName,
        job_title: updates.jobTitle,
        phone: updates.phone,
      }).eq('id', userId.value)
      if (error) {
        errorMessage.value = `Could not save your profile: ${error.message}`
        console.error(errorMessage.value, error)
        return false
      }
      await loadProfile(userId.value)
      return !errorMessage.value
    }

    profile.value = { ...profile.value, ...updates }
    userFirstName.value = profile.value.firstName
    localStorage.setItem('northstar-user-first-name', userFirstName.value)
    localStorage.setItem('northstar-user-profile', JSON.stringify(profile.value))
    const savedAccount = localStorage.getItem(accountKey)
    if (savedAccount) {
      const account = JSON.parse(savedAccount) as LegacyAccount
      localStorage.setItem(accountKey, JSON.stringify({ ...account, ...updates }))
    }
    return true
  }

  async function uploadAvatar (file: File) {
    errorMessage.value = ''
    if (!isSupabaseConfigured || !supabase || !userId.value) {
      errorMessage.value = 'Profile photo upload requires an active Supabase session.'
      return false
    }
    const extension = file.name.split('.').at(-1)?.replace(/[^a-z0-9]/gi, '') || 'image'
    const path = `${userId.value}/${crypto.randomUUID()}.${extension}`
    const { error: uploadError } = await supabase.storage.from('profile-avatars').upload(path, file, {
      contentType: file.type,
      upsert: false,
    })
    if (uploadError) {
      errorMessage.value = `Could not upload profile photo: ${uploadError.message}`
      console.error(errorMessage.value, uploadError)
      return false
    }
    const { error: profileError } = await supabase.from('profiles').update({ avatar_url: path }).eq('id', userId.value)
    if (profileError) {
      errorMessage.value = `Photo uploaded, but the profile could not be updated: ${profileError.message}`
      console.error(errorMessage.value, profileError)
      return false
    }
    await loadProfile(userId.value)
    return !errorMessage.value
  }

  async function logout () {
    errorMessage.value = ''
    if (isSupabaseConfigured && supabase) {
      const { error } = await supabase.auth.signOut()
      if (error) {
        errorMessage.value = `Could not sign out from Supabase: ${error.message}`
        console.error(errorMessage.value, error)
        return false
      }
    }
    clearAuthenticatedUser()
    return true
  }

  function applySupabaseUser (user: User) {
    userId.value = user.id
    userEmail.value = user.email ?? ''
    isAuthenticated.value = true
    isAdmin.value = false
    profile.value = {
      ...profile.value,
      firstName: String(user.user_metadata.first_name ?? profile.value.firstName ?? ''),
      lastName: String(user.user_metadata.last_name ?? profile.value.lastName ?? ''),
      role: 'employee',
    }
    userFirstName.value = profile.value.firstName || userEmail.value.split('@', 1)[0]
    localStorage.setItem(storageKey, 'true')
    localStorage.setItem('northstar-user-email', userEmail.value)
    localStorage.setItem('northstar-user-first-name', userFirstName.value)
  }

  function saveLocalSession () {
    localStorage.setItem(storageKey, 'true')
    localStorage.setItem('northstar-user-role', profile.value.role)
    localStorage.setItem('northstar-user-email', userEmail.value)
    localStorage.setItem('northstar-user-first-name', userFirstName.value)
    localStorage.setItem('northstar-user-profile', JSON.stringify(profile.value))
  }

  function clearAuthenticatedUser () {
    isAuthenticated.value = false
    isAdmin.value = false
    userId.value = ''
    userEmail.value = ''
    userFirstName.value = ''
    profile.value = emptyProfile()
    localStorage.removeItem(storageKey)
    localStorage.removeItem('northstar-user-role')
    localStorage.removeItem('northstar-user-email')
    localStorage.removeItem('northstar-user-first-name')
    localStorage.removeItem('northstar-user-profile')
  }

  function dispose () {
    authSubscription?.unsubscribe()
    authSubscription = null
  }

  return {
    isAuthenticated,
    isAdmin,
    isPasswordRecovery,
    userId,
    userEmail,
    userFirstName,
    profile,
    ready,
    errorMessage,
    initialize,
    login,
    signup,
    resetPassword,
    updatePassword,
    saveProfile,
    uploadAvatar,
    logout,
    dispose,
  }
})

function readCachedProfile (): UserProfile {
  const saved = localStorage.getItem('northstar-user-profile')
  if (!saved) {
    return { ...emptyProfile(), firstName: localStorage.getItem('northstar-user-first-name') ?? '' }
  }

  const profile = JSON.parse(saved) as Partial<UserProfile>
  return { ...emptyProfile(), ...profile }
}

function profileFromLegacy (account: LegacyAccount): UserProfile {
  return {
    ...emptyProfile(),
    firstName: account.firstName ?? '',
    lastName: account.lastName ?? '',
    jobTitle: account.jobTitle ?? '',
    department: account.department ?? '',
    phone: account.phone ?? '',
    photoUrl: account.photoUrl ?? '',
    role: account.role ?? 'employee',
  }
}
