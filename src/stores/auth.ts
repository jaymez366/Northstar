import type { User } from '@supabase/supabase-js'
import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { isSupabaseConfigured, supabase, supabaseConfigurationError } from '../../lib/supabase.js'
import { validateNorthstarPhoto } from '@/utils/registrationPhoto'

const signupConfirmationRedirect = () => `${window.location.origin}/auth/callback`
const administratorEmail = 'northstaradmin34@gmail.com'
const emailConfirmationCallbackDetected = (() => {
  if (typeof window === 'undefined' || !window.location.pathname.endsWith('/auth/callback')) return false
  const url = new URL(window.location.href)
  const hash = new URLSearchParams(url.hash.slice(1))
  return url.searchParams.has('code') || url.searchParams.has('token_hash')
    || url.searchParams.has('error') || url.searchParams.has('error_description')
    || (hash.has('access_token') && ['signup', 'email'].includes(hash.get('type') ?? ''))
    || hash.has('error') || hash.has('error_description')
})()
const isUuid = (value: string | null | undefined): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)

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
  rejectionReason: string
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
    rejectionReason: '',
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
  const registrationSubmissionSucceeded = ref(false)
  const profile = ref<UserProfile>(emptyProfile())
  const profileLoaded = ref(false)
  const employeeRegistrationComplete = computed(() => profile.value.registrationCompleted
    && Boolean(
      profile.value.firstName.trim()
      && profile.value.lastName.trim()
      && profile.value.phone.trim()
      && profile.value.department.trim()
      && profile.value.jobTitle.trim()
      && profile.value.employmentType.trim()
      && profile.value.officeLocation.trim(),
    ))
  const canAccessEmployeeWorkspace = computed(() => isAdmin.value
    || (emailVerified.value
      && profileLoaded.value
      && employeeRegistrationComplete.value
      && profile.value.approvalStatus === 'approved'
      && profile.value.status === 'active'))
  const ready = ref(false)
  const errorMessage = ref('')
  let initialization: Promise<void> | null = null
  let profileLoad: { userId: string, promise: Promise<void> } | null = null
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
        errorMessage.value = `Northstar Supabase is not configured in this build. ${supabaseConfigurationError} Add the missing variable(s) to the hosting build environment and redeploy.`
        clearAuthenticatedUser()
        ready.value = true
        return
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

      const { data, error } = await supabase.auth.getSession()
      if (error) {
        errorMessage.value = `Could not restore your Supabase session: ${error.message}`
        console.error(errorMessage.value, error)
        clearAuthenticatedUser()
      } else if (data.session) {
        applySupabaseUser(data.session.user)
        isPasswordRecovery.value ||= window.location.hash.includes('type=recovery')
        await loadProfile(data.session.user.id)
      } else {
        clearAuthenticatedUser()
      }
      ready.value = true
    })()

    return initialization
  }

  async function loadProfile (id: string) {
    if (!supabase || !isSupabaseConfigured || !isUuid(id) || id !== userId.value) {
      return
    }
    if (profileLoad?.userId === id) {
      return profileLoad.promise
    }

    const promise = loadProfileRecord(id)
    profileLoad = { userId: id, promise }
    try {
      await promise
    } finally {
      if (profileLoad?.promise === promise) {
        profileLoad = null
      }
    }
  }

  async function loadProfileRecord (id: string) {
    if (!supabase || !isSupabaseConfigured || !isUuid(id) || id !== userId.value) {
      return
    }
    profileLoaded.value = false
    // Read the signed-in user's canonical profile row under the existing RLS
    // policies. The admin registration RPC reads profiles.registration_completed
    // directly, so login routing must use that same source of truth.
    const { data: ownProfile, error } = await supabase
      .from('profiles')
      .select('first_name,last_name,job_title,department_id,phone_number,avatar_url,role,employment_status,approval_status,rejection_reason,registration_completed,employee_id,employment_type,office_location,date_of_joining,manager_name,bio,departments(name)')
      .eq('id', id)
      .maybeSingle()

    if (error) {
      errorMessage.value = `Could not load your profile from Supabase: ${error.message}`
      console.error(errorMessage.value, error)
      return
    }
    if (id !== userId.value) {
      return
    }

    if (!ownProfile) {
      errorMessage.value = 'Your Supabase account has no readable employee profile. Check the profile row and its row-level security policy.'
      return
    }

    let rejectionReason = ownProfile.rejection_reason ?? ''
    let profileLoadError = ''
    const departmentRelation = Array.isArray(ownProfile.departments)
      ? ownProfile.departments[0]
      : ownProfile.departments

    profile.value = {
      firstName: ownProfile.first_name ?? '',
      lastName: ownProfile.last_name ?? '',
      jobTitle: ownProfile.job_title ?? '',
      department: departmentRelation?.name ?? '',
      departmentId: ownProfile.department_id ?? '',
      phone: ownProfile.phone_number ?? '',
      photoUrl: '',
      avatarPath: ownProfile.avatar_url ?? '',
      role: ownProfile.role ?? 'employee',
      status: ownProfile.employment_status ?? 'inactive',
      approvalStatus: ownProfile.approval_status ?? 'pending',
      rejectionReason,
      registrationCompleted: ownProfile.registration_completed ?? false,
      employeeId: ownProfile.employee_id ?? '',
      employmentType: ownProfile.employment_type ?? '',
      officeLocation: ownProfile.office_location ?? '',
      dateOfJoining: ownProfile.date_of_joining ?? '',
      managerName: ownProfile.manager_name ?? '',
      bio: ownProfile.bio ?? '',
    }
    let avatarLoadError = profileLoadError
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
    if (id !== userId.value) {
      return
    }
    userFirstName.value = profile.value.firstName
    isAdmin.value = isDesignatedAdministrator()
    profileLoaded.value = true
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
    const { data, error } = await supabase.functions.invoke<{
      status: 'accepted'
    }>('resend-confirmation', {
      body: {
        email: email.trim(),
        emailRedirectTo: signupConfirmationRedirect(),
      },
    })
    if (error) {
      errorMessage.value = 'We could not process that request right now. Please wait a moment and try again.'
      console.error('Supabase signup confirmation resend failed', error)
      return false
    }
    if (data?.status !== 'accepted') {
      errorMessage.value = 'We could not process that request right now. Please try again later.'
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
      const errorText = error.message.toLowerCase()
      if (error.code === 'email_not_confirmed') {
        errorMessage.value = 'Verify your email address before signing in. You can resend the confirmation email below.'
      } else if (errorText.includes('invalid path specified in request url') || error.status === 404) {
        errorMessage.value = 'Northstar could not reach the Supabase authentication endpoint. Check the project URL configuration and try again.'
      } else if (!error.status || error.status >= 500) {
        errorMessage.value = 'Northstar could not contact the authentication service. Please try again shortly.'
      } else {
        errorMessage.value = 'That email or password is not recognized.'
      }
      console.error('Supabase sign-in request failed', {
        endpoint: '/auth/v1/token?grant_type=password',
        status: error.status,
        code: error.code ?? 'unknown',
      })
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
    if (!profileLoaded.value && !isAdmin.value) {
      return false
    }
    return true
  }

  async function signup (email: string, password: string, fullName: string) {
    errorMessage.value = ''
    const nameParts = fullName.trim().split(/\s+/)
    const firstName = nameParts[0] ?? ''
    const lastName = nameParts.slice(1).join(' ')

    if (!isSupabaseConfigured || !supabase) {
      errorMessage.value = `Account registration is unavailable because this build has no Northstar Supabase configuration. ${supabaseConfigurationError} Add the missing variable(s) to the hosting build environment and redeploy.`
      return { success: false, requiresEmailConfirmation: false }
    }

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { first_name: firstName, last_name: lastName },
        emailRedirectTo: signupConfirmationRedirect(),
      },
    })
    if (error) {
      if (error.code === 'user_already_exists' || error.code === 'email_exists') {
        errorMessage.value = 'An account may already exist for this email. Sign in or request a confirmation link if needed.'
      } else if (!error.status || error.status >= 500 || /fetch|network|timeout/i.test(error.message)) {
        errorMessage.value = 'Northstar could not reach the account service. Check your connection and try again.'
      } else {
        errorMessage.value = 'We could not create this account. Check the details and try again.'
      }
      console.error('Supabase signup request failed', {
        endpoint: '/auth/v1/signup',
        status: error.status,
        code: error.code ?? 'unknown',
      })
      return { success: false, requiresEmailConfirmation: false }
    }

    if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) {
      errorMessage.value = 'An account may already exist for this email. Sign in or request a confirmation link if needed.'
      return { success: false, requiresEmailConfirmation: false }
    }
    if (!data.user) {
      errorMessage.value = 'Northstar could not confirm that the account was created. Please try again.'
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
    if (!profileLoaded.value || profile.value.approvalStatus !== 'pending'
      || !profile.value.registrationCompleted || profile.value.status !== 'inactive') {
      errorMessage.value = 'Your registration was submitted, but Northstar could not confirm its pending approval status. Refresh your profile or contact the administrator before retrying.'
      return false
    }
    profile.value = {
      ...profile.value,
      firstName: registration.firstName.trim(),
      lastName: registration.lastName.trim(),
      phone: registration.phoneNumber.trim(),
      department: registration.department,
      jobTitle: registration.jobTitle.trim(),
      employeeId: registration.employeeId.trim(),
      employmentType: registration.employmentType,
      officeLocation: registration.officeLocation.trim(),
      dateOfJoining: registration.dateOfJoining,
      managerName: registration.managerName.trim(),
      bio: registration.bio.trim(),
      approvalStatus: 'pending',
      rejectionReason: '',
      registrationCompleted: true,
      status: 'inactive',
    }
    profileLoaded.value = true
    return true
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
      errorMessage.value = 'We could not process that password reset request. Please try again later.'
      console.error('Supabase password reset request failed', {
        status: error.status,
        code: error.code ?? 'unknown',
      })
      return false
    }
    return true
  }

  async function updatePassword (password: string) {
    errorMessage.value = ''
    if (!isPasswordRecovery.value) {
      errorMessage.value = 'Open the password reset link from your email before choosing a new password.'
      return false
    }
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
    const { error: signOutError } = await supabase.auth.signOut()
    if (signOutError) {
      errorMessage.value = `Your password was updated, but Northstar could not end the recovery session. Sign out before continuing.`
      console.error('Could not end Supabase password recovery session', signOutError)
      return false
    }
    clearAuthenticatedUser()
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
    const photoValidationError = await validateNorthstarPhoto(file)
    if (photoValidationError) {
      errorMessage.value = photoValidationError
      return false
    }
    if (!isSupabaseConfigured || !supabase || !isUuid(userId.value)) {
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

  async function uploadRegistrationPhoto (file: File, useAsProfilePhoto: boolean) {
    errorMessage.value = ''
    const photoValidationError = await validateNorthstarPhoto(file)
    if (photoValidationError) {
      errorMessage.value = photoValidationError
      return false
    }
    if (!isSupabaseConfigured || !supabase || !isUuid(userId.value)) {
      errorMessage.value = 'Registration photo upload requires an active Supabase session.'
      return false
    }
    const extension = file.name.split('.').at(-1)?.replace(/[^a-z0-9]/gi, '') || 'image'
    const path = `${userId.value}/${crypto.randomUUID()}.${extension}`
    const { error: uploadError } = await supabase.storage.from('profile-avatars').upload(path, file, {
      contentType: file.type,
      upsert: false,
    })
    if (uploadError) {
      errorMessage.value = `Could not upload registration photo: ${uploadError.message}`
      console.error(errorMessage.value, uploadError)
      return false
    }
    const { error: saveError } = await supabase.rpc('northstar_save_registration_photo', {
      p_storage_path: path,
      p_use_as_profile_photo: useAsProfilePhoto,
    })
    if (saveError) {
      errorMessage.value = `Photo uploaded, but its registration choice could not be saved: ${saveError.message}`
      console.error(errorMessage.value, saveError)
      return false
    }
    if (useAsProfilePhoto) {
      await loadProfile(userId.value)
      if (!profileLoaded.value) return false
    }
    return true
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
      profileLoaded.value = false
      registrationSubmissionSucceeded.value = false
    }
    userId.value = user.id
    userEmail.value = user.email ?? ''
    isAuthenticated.value = true
    emailVerified.value = Boolean(user.email_confirmed_at)
    isAdmin.value = isDesignatedAdministrator()
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
    profileLoaded.value = false
    profile.value = emptyProfile()
    isPasswordRecovery.value = false
    registrationSubmissionSucceeded.value = false
  }

  function isDesignatedAdministrator () {
    return isAuthenticated.value
      && emailVerified.value
      && userEmail.value.trim().toLowerCase() === administratorEmail
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
    emailConfirmationCallbackDetected,
    registrationSubmissionSucceeded,
    userId,
    userEmail,
    userFirstName,
    profile,
    profileLoaded,
    employeeRegistrationComplete,
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
    uploadRegistrationPhoto,
    canAccessEmployeeWorkspace,
    logout,
    dispose,
    refreshProfile,
  }
})
