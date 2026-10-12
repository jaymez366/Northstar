import type { User } from '@supabase/supabase-js'
import { defineStore } from 'pinia'
import { ref } from 'vue'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

for (const legacyKey of [
  'northstar-authenticated',
  'northstar-account',
  'northstar-user-role',
  'northstar-user-email',
  'northstar-user-first-name',
  'northstar-user-profile',
]) {
  localStorage.removeItem(legacyKey)
}

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
  const isAuthenticated = ref(false)
  const isAdmin = ref(false)
  const userId = ref('')
  const userEmail = ref('')
  const userFirstName = ref('')
  const isPasswordRecovery = ref(false)
  const profile = ref<UserProfile>(emptyProfile())
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
      if (!isSupabaseConfigured || !supabase) {
        errorMessage.value = 'Northstar Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to enable account access.'
        clearAuthenticatedUser()
        ready.value = true
        return
      }

      const { data, error } = await supabase.auth.getSession()
      if (error) {
        errorMessage.value = `Could not restore your Supabase session: ${error.message}`
        console.error(errorMessage.value, error)
        clearAuthenticatedUser()
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
      ready.value = true
    })()

    return initialization
  }

  async function loadProfile (id: string) {
    if (!supabase || !isSupabaseConfigured || id !== userId.value) {
      return
    }
    const { data, error } = await supabase.rpc('get_my_profile')

    if (error) {
      isAdmin.value = false
      errorMessage.value = `Could not load your profile from Supabase: ${error.message}`
      console.error(errorMessage.value, error)
      return
    }

    const ownProfile = data?.[0]
    if (!ownProfile) {
      isAdmin.value = false
      errorMessage.value = 'Your Supabase account has no profile yet. Apply the profile trigger SQL in Supabase.'
      return
    }

    profile.value = {
      firstName: ownProfile.first_name ?? '',
      lastName: ownProfile.last_name ?? '',
      jobTitle: ownProfile.job_title ?? '',
      department: ownProfile.department_name ?? '',
      departmentId: ownProfile.department_id ?? '',
      phone: ownProfile.phone_number ?? '',
      photoUrl: '',
      avatarPath: ownProfile.avatar_url ?? '',
      role: ownProfile.role ?? 'employee',
      status: ownProfile.employment_status ?? 'active',
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
    errorMessage.value = avatarLoadError
  }

  async function login (email: string, password: string) {
    errorMessage.value = ''

    if (!isSupabaseConfigured || !supabase) {
      errorMessage.value = 'Account access is unavailable until Northstar Supabase is configured.'
      return false
    }

    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) {
      errorMessage.value = 'That email or password is not recognized.'
      console.error('Supabase sign-in failed', error)
      return false
    }
    if (!data.user) {
      errorMessage.value = 'Supabase did not return a user after sign-in.'
      return false
    }

    applySupabaseUser(data.user)
    await loadProfile(data.user.id)
    return true
  }

  async function signup (email: string, password: string, fullName: string) {
    errorMessage.value = ''
    const nameParts = fullName.trim().split(/\s+/)
    const firstName = nameParts[0] ?? ''
    const lastName = nameParts.slice(1).join(' ')

    if (!isSupabaseConfigured || !supabase) {
      errorMessage.value = 'Account registration is unavailable until Northstar Supabase is configured.'
      return { success: false, requiresEmailConfirmation: false }
    }

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { first_name: firstName, last_name: lastName } },
    })
    if (error) {
      errorMessage.value = error.message
      return { success: false, requiresEmailConfirmation: false }
    }

    if (data.session && data.user) {
      applySupabaseUser(data.user)
      await loadProfile(data.user.id)
      return { success: true, requiresEmailConfirmation: false }
    }

    return { success: true, requiresEmailConfirmation: true }
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
        phone_number: updates.phone,
      }).eq('id', userId.value)
      if (error) {
        errorMessage.value = `Could not save your profile: ${error.message}`
        console.error(errorMessage.value, error)
        return false
      }
      await loadProfile(userId.value)
      return !errorMessage.value
    }

    errorMessage.value = 'Profile updates require a configured Northstar Supabase connection.'
    return false
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
      firstName: String(user.user_metadata.first_name ?? ''),
      lastName: String(user.user_metadata.last_name ?? ''),
      role: 'employee',
    }
    userFirstName.value = profile.value.firstName || userEmail.value.split('@', 1)[0]
  }

  function clearAuthenticatedUser () {
    isAuthenticated.value = false
    isAdmin.value = false
    userId.value = ''
    userEmail.value = ''
    userFirstName.value = ''
    profile.value = emptyProfile()
    isPasswordRecovery.value = false
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
