import type { User } from '@supabase/supabase-js'
import { defineStore } from 'pinia'
import { ref } from 'vue'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

const signupConfirmationRedirect = 'https://northstar-1k1.pages.dev/auth/callback'

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
  approvalStatus: 'pending' | 'approved' | 'rejected'
  registrationCompleted: boolean
  employeeId: string
  employmentType: string
  officeLocation: string
  dateOfJoining: string
  managerName: string
  bio: string
}

export type EmployeeRegistration = {
  firstName: string
  lastName: string
  phoneNumber: string
  department: string
  jobTitle: string
  employeeId: string
  employmentType: string
  officeLocation: string
  dateOfJoining: string
  managerName: string
  bio: string
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
    status: 'inactive',
    approvalStatus: 'pending',
    registrationCompleted: false,
    employeeId: '',
    employmentType: '',
    officeLocation: '',
    dateOfJoining: '',
    managerName: '',
    bio: '',
  }
}

export const useAuthStore = defineStore('auth', () => {
  const isAuthenticated = ref(false)
  const emailVerified = ref(false)
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
      approvalStatus: ownProfile.approval_status ?? 'pending',
      registrationCompleted: ownProfile.registration_completed ?? false,
      employeeId: ownProfile.employee_id ?? '',
      employmentType: ownProfile.employment_type ?? '',
      officeLocation: ownProfile.office_location ?? '',
      dateOfJoining: ownProfile.date_of_joining ?? '',
      managerName: ownProfile.manager_name ?? '',
      bio: ownProfile.bio ?? '',
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

  async function refreshProfile () {
    if (userId.value) {
      await loadProfile(userId.value)
    }
  }

  async function resendSignupConfirmation (email: string) {
    errorMessage.value = ''
    if (!isSupabaseConfigured || !supabase) {
      errorMessage.value = 'Resending a confirmation email requires a configured Northstar Supabase connection.'
      return false
    }
    const { error } = await supabase.auth.resend({
      type: 'signup',
      email,
      options: { emailRedirectTo: signupConfirmationRedirect },
    })
    if (error) {
      errorMessage.value = error.message
      console.error('Supabase signup confirmation resend failed', error)
      return false
    }
    return true
  }

  async function login (email: string, password: string) {
    errorMessage.value = ''

    if (!isSupabaseConfigured || !supabase) {
      errorMessage.value = 'Account access is unavailable until Northstar Supabase is configured.'
      return false
    }

    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) {
      errorMessage.value = error.code === 'email_not_confirmed'
        ? 'Verify your email address before signing in. You can resend the confirmation email below.'
        : 'That email or password is not recognized.'
      console.error('Supabase sign-in failed', error)
      return false
    }
    if (!data.user) {
      errorMessage.value = 'Supabase did not return a user after sign-in.'
      return false
    }

    applySupabaseUser(data.user)
    if (!data.user.email_confirmed_at) {
      errorMessage.value = 'Verify your email address before signing in. You can resend the confirmation email below.'
      await supabase.auth.signOut()
      clearAuthenticatedUser()
      return false
    }
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
      options: {
        data: { first_name: firstName, last_name: lastName },
        emailRedirectTo: signupConfirmationRedirect,
      },
    })
    if (error) {
      errorMessage.value = error.message
      return { success: false, requiresEmailConfirmation: false }
    }

    if (data.session && data.user) {
      if (!data.user.email_confirmed_at) {
        await supabase.auth.signOut()
        clearAuthenticatedUser()
        errorMessage.value = 'Email confirmations are disabled for this Northstar Supabase project. Enable email confirmations to require verification before registration.'
        return { success: false, requiresEmailConfirmation: false }
      }
      applySupabaseUser(data.user)
      await loadProfile(data.user.id)
      return { success: true, requiresEmailConfirmation: false }
    }

    return { success: true, requiresEmailConfirmation: true }
  }

  async function completeEmployeeRegistration (registration: EmployeeRegistration) {
    errorMessage.value = ''
    if (!isSupabaseConfigured || !supabase || !userId.value || !emailVerified.value) {
      errorMessage.value = 'Verify your Northstar email before completing employee registration.'
      return false
    }
    const { error } = await supabase.rpc('complete_my_employee_registration', {
      p_first_name: registration.firstName.trim(),
      p_last_name: registration.lastName.trim(),
      p_phone_number: registration.phoneNumber.trim(),
      p_department: registration.department,
      p_job_title: registration.jobTitle.trim(),
      p_employee_id: registration.employeeId.trim() || null,
      p_employment_type: registration.employmentType,
      p_office_location: registration.officeLocation.trim(),
      p_date_of_joining: registration.dateOfJoining || null,
      p_manager_name: registration.managerName.trim() || null,
      p_bio: registration.bio.trim() || null,
    })
    if (error) {
      errorMessage.value = `Could not save your employee registration: ${error.message}`
      console.error(errorMessage.value, error)
      return false
    }
    await loadProfile(userId.value)
    return profile.value.registrationCompleted
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
      const { error } = await supabase.rpc('update_my_employee_profile', {
        p_first_name: updates.firstName ?? profile.value.firstName,
        p_last_name: updates.lastName ?? profile.value.lastName,
        p_job_title: updates.jobTitle ?? profile.value.jobTitle,
        p_phone_number: updates.phone ?? profile.value.phone,
        p_bio: updates.bio ?? profile.value.bio,
      })
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
    if (userId.value && userId.value !== user.id) {
      profile.value = emptyProfile()
    }
    userId.value = user.id
    userEmail.value = user.email ?? ''
    isAuthenticated.value = true
    emailVerified.value = Boolean(user.email_confirmed_at)
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
    emailVerified.value = false
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
    emailVerified,
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
    resendSignupConfirmation,
    completeEmployeeRegistration,
    resetPassword,
    updatePassword,
    saveProfile,
    uploadAvatar,
    logout,
    dispose,
    refreshProfile,
  }
})
