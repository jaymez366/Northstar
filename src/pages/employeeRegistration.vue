<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'
  import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'
  import { validateNorthstarPhoto } from '@/utils/registrationPhoto'

  const auth = useAuthStore()
  const router = useRouter()
  const saving = ref(false)
  const error = ref('')
  const photo = ref<File | null>(null)
  const photoChoice = ref<boolean | null>(null)
  const photoValidating = ref(false)
  const fieldErrors = ref<Record<string, string>>({})
  const departmentRecords = ref<{ id: string, name: string }[]>([])
  const departmentLoading = ref(false)
  const departmentError = ref('')
  const correctionLoading = ref(false)
  const correctionError = ref('')
  const correctionFields = ref<string[]>([])
  const correctionSnapshot = ref<Record<string, string | null>>({})
  const correctionFieldLabels: Record<string, string> = {
    first_name: 'First name',
    last_name: 'Last name',
    phone_number: 'Phone number',
    department: 'Department',
    job_title: 'Job title',
    employee_id: 'Employee ID',
    employment_type: 'Employment type',
    office_location: 'Office location',
    date_of_joining: 'Date of joining',
    manager_name: "Manager's name",
    bio: 'Short introduction',
  }
  const departments = computed(() => departmentRecords.value.map(department => department.name))
  const employmentTypes = ['Full-time', 'Part-time', 'Contract', 'Intern', 'Other']
  const form = reactive({
    firstName: auth.profile.firstName,
    lastName: auth.profile.lastName,
    phoneNumber: auth.profile.phone,
    department: auth.profile.department,
    jobTitle: auth.profile.jobTitle,
    employeeId: auth.profile.employeeId,
    employmentType: auth.profile.employmentType,
    officeLocation: auth.profile.officeLocation,
    dateOfJoining: auth.profile.dateOfJoining,
    managerName: auth.profile.managerName,
    bio: auth.profile.bio,
  })
  const today = new Date()
  const latestJoiningDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

  onMounted(() => {
    void loadDepartments()
    void loadCorrectionRequirements()
  })

  const isCorrectionRequired = (field: string) => correctionFields.value.includes(field)

  async function loadCorrectionRequirements () {
    if (auth.profile.approvalStatus !== 'rejected') return
    correctionLoading.value = true
    correctionError.value = ''
    if (!isSupabaseConfigured || !supabase) {
      correctionError.value = 'Correction requirements could not be checked because Northstar Supabase is not configured.'
      correctionLoading.value = false
      return
    }
    try {
      const { data, error: requirementsError } = await supabase.rpc('northstar_get_my_registration_correction_requirements')
      if (requirementsError) {
        correctionError.value = `Could not load required corrections: ${requirementsError.message}`
        console.error(correctionError.value, requirementsError)
        return
      }
      const requirements = Array.isArray(data) ? data[0] : data
      if (!requirements || !Array.isArray(requirements.correction_fields)) {
        correctionError.value = 'No active correction requirements were returned for this rejected registration. Contact the administrator.'
        return
      }
      correctionFields.value = requirements.correction_fields.filter((field: unknown): field is string =>
        typeof field === 'string')
      if (correctionFields.value.length === 0) {
        correctionError.value = 'This rejection predates correction requirements or has no selected fields. Ask the administrator to issue a new rejection with correction fields; no requirements were inferred.'
        return
      }
      if (!requirements.registration_snapshot || typeof requirements.registration_snapshot !== 'object'
        || correctionFields.value.some((field: string) =>
          !Object.prototype.hasOwnProperty.call(requirements.registration_snapshot, field))) {
        correctionError.value = 'The rejected registration snapshot is unavailable or incomplete. Contact the administrator before resubmitting.'
        return
      }
      correctionSnapshot.value = requirements.registration_snapshot as Record<string, string | null>
    } catch (requirementsError) {
      correctionError.value = 'Could not load required corrections. Please try again.'
      console.error(correctionError.value, requirementsError)
    } finally {
      correctionLoading.value = false
    }
  }

  async function loadDepartments () {
    departmentLoading.value = true
    departmentError.value = ''
    if (!isSupabaseConfigured || !supabase) {
      departmentError.value = 'Departments cannot be checked until Northstar Supabase is configured.'
      departmentLoading.value = false
      return
    }
    if (!auth.isAuthenticated || !auth.emailVerified) {
      departmentError.value = 'Sign in with your email-confirmed Northstar account to load departments.'
      departmentLoading.value = false
      return
    }
    try {
      const { data, error: loadError } = await supabase.from('departments').select('id,name').order('name')
      if (loadError) {
        departmentError.value = 'Northstar could not load departments. Please try again or contact the administrator.'
        console.error('Could not load registration departments from Supabase', loadError)
        return
      }
      departmentRecords.value = (data ?? []).filter(row => typeof row.id === 'string' && typeof row.name === 'string')
      if (departmentRecords.value.length === 0) {
        departmentError.value = 'No departments are visible to this account. The administrator may need to check department read access.'
        console.warn('The authenticated department query returned no visible rows; check the departments SELECT policy and role helper.')
      }
    } catch (loadError) {
      departmentError.value = 'Northstar could not load the available departments. Please try again.'
      console.error('Could not load registration departments', loadError)
    } finally {
      departmentLoading.value = false
    }
  }

  function validateForm () {
    const errors: Record<string, string> = {}
    if (!form.firstName.trim()) errors.firstName = 'Enter your first name.'
    if (!form.lastName.trim()) errors.lastName = 'Enter your last name.'
    if (!/^\+?[\d\s().-]{7,24}$/.test(form.phoneNumber.trim()) || form.phoneNumber.replace(/\D/g, '').length < 7) {
      errors.phoneNumber = 'Enter a valid phone number with at least seven digits.'
    }
    if (!departments.value.includes(form.department.trim())) errors.department = 'Choose a department currently listed in Northstar.'
    if (!form.jobTitle.trim()) errors.jobTitle = 'Enter your job title.'
    if (!employmentTypes.includes(form.employmentType)) errors.employmentType = 'Choose a valid employment type.'
    if (!form.officeLocation.trim()) errors.officeLocation = 'Enter your office location or branch.'
    if (form.dateOfJoining) {
      const joiningDate = new Date(`${form.dateOfJoining}T00:00:00`)
      const joiningDateIsReal = /^\d{4}-\d{2}-\d{2}$/.test(form.dateOfJoining)
        && !Number.isNaN(joiningDate.getTime())
        && `${joiningDate.getFullYear()}-${String(joiningDate.getMonth() + 1).padStart(2, '0')}-${String(joiningDate.getDate()).padStart(2, '0')}` === form.dateOfJoining
      if (!joiningDateIsReal || form.dateOfJoining > latestJoiningDate) {
        errors.dateOfJoining = 'Enter a valid date of joining that is not in the future.'
      }
    }
    if (auth.profile.approvalStatus === 'rejected') {
      const submittedValues: Record<string, string> = {
        first_name: form.firstName,
        last_name: form.lastName,
        phone_number: form.phoneNumber,
        department: form.department,
        job_title: form.jobTitle,
        employee_id: form.employeeId,
        employment_type: form.employmentType,
        office_location: form.officeLocation,
        date_of_joining: form.dateOfJoining,
        manager_name: form.managerName,
        bio: form.bio,
      }
      const errorFieldNames: Record<string, string> = {
        first_name: 'firstName',
        last_name: 'lastName',
        phone_number: 'phoneNumber',
        job_title: 'jobTitle',
        employment_type: 'employmentType',
        office_location: 'officeLocation',
      }
      for (const field of correctionFields.value) {
        const errorField = errorFieldNames[field] ?? field
        const submitted = submittedValues[field]?.trim() ?? ''
        const original = correctionSnapshot.value[field]?.trim() ?? ''
        if (!submitted) {
          errors[errorField] = 'This field is required by the administrator before resubmission.'
        } else if ((field === 'department'
          ? submitted.toLowerCase() === original.toLowerCase()
          : submitted === original)) {
          errors[errorField] = 'Change this field from the value in the rejected registration.'
        }
      }
    }
    fieldErrors.value = errors
    return Object.keys(errors).length ? 'Review the highlighted registration fields.' : ''
  }

  async function submitRegistration () {
    error.value = validateForm()
    if (correctionLoading.value || departmentLoading.value || photoValidating.value) {
      error.value = 'Wait for department and photo validation to finish.'
    } else if (correctionError.value) {
      error.value = correctionError.value
    } else if (departmentError.value) {
      error.value = departmentError.value
    } else if (photo.value && photoChoice.value === null) {
      error.value = 'Choose whether this photo should be used as your Northstar profile picture.'
    }
    if (error.value || saving.value) return

    saving.value = true
    try {
      const saved = await auth.completeEmployeeRegistration({
        ...form,
        firstName: form.firstName.trim(),
        lastName: form.lastName.trim(),
        phoneNumber: form.phoneNumber.trim(),
        department: form.department.trim(),
        jobTitle: form.jobTitle.trim(),
        employeeId: form.employeeId.trim(),
        officeLocation: form.officeLocation.trim(),
        managerName: form.managerName.trim(),
        bio: form.bio.trim(),
      })
      if (!saved) {
        error.value = auth.errorMessage || 'Your registration could not be saved.'
        return
      }
      if (photo.value) {
        const uploaded = await auth.uploadRegistrationPhoto(photo.value, photoChoice.value === true)
        if (!uploaded) {
          error.value = auth.errorMessage || 'Your profile photo could not be uploaded.'
          return
        }
      }
      auth.registrationSubmissionSucceeded = true
      await router.replace('/pending-approval')
    } catch (submitError) {
      error.value = auth.errorMessage || 'Your registration could not be saved. Please try again.'
      console.error('Employee registration submission failed', submitError)
    } finally {
      saving.value = false
    }
  }

  async function selectPhoto (event: Event) {
    const input = event.target as HTMLInputElement
    const file = input.files?.[0]
    photo.value = null
    photoChoice.value = null
    error.value = ''
    if (!file) return
    photoValidating.value = true
    try {
      const validationError = await validateNorthstarPhoto(file)
      if (validationError) {
        input.value = ''
        error.value = validationError
        return
      }
      photo.value = file
    } finally {
      photoValidating.value = false
    }
  }
</script>

<template>
  <main class="registration-page">
    <header class="page-heading">
      <div>
        <p class="eyebrow">EMPLOYEE ONBOARDING</p>
        <h1>Complete your registration</h1>
        <p>{{ auth.profile.approvalStatus === 'rejected'
          ? 'Correct every field selected by the administrator. Each required correction must be changed from the rejected registration.'
          : 'Provide your work details. An administrator will review your registration before workspace access is enabled.' }}</p>
      </div>
    </header>

    <section v-if="auth.profile.approvalStatus === 'rejected'" class="correction-notice surface-card" aria-live="polite">
      <strong>Administrator feedback</strong>
      <p v-if="auth.profile.rejectionReason">{{ auth.profile.rejectionReason }}</p>
      <p v-if="correctionLoading">Loading required corrections…</p>
      <p v-else-if="correctionError" class="form-error">{{ correctionError }}</p>
      <p v-else>Fields to correct: {{ correctionFields.map(field => correctionFieldLabels[field] ?? field).join(', ') }}</p>
    </section>

    <form class="registration-form surface-card" @submit.prevent="submitRegistration">
      <section class="registration-section">
        <div class="section-title">
          <h2>Personal details</h2>
          <p>Your verified Northstar account is used to identify your profile.</p>
        </div>

        <div class="registration-grid">
          <label>First name <span>*</span>
            <input v-model="form.firstName" :aria-invalid="Boolean(fieldErrors.firstName)" autocomplete="given-name" maxlength="80" required>
            <small v-if="fieldErrors.firstName" class="form-field-error">{{ fieldErrors.firstName }}</small>
          </label>

          <label>Last name <span>*</span>
            <input v-model="form.lastName" :aria-invalid="Boolean(fieldErrors.lastName)" autocomplete="family-name" maxlength="80" required>
            <small v-if="fieldErrors.lastName" class="form-field-error">{{ fieldErrors.lastName }}</small>
          </label>

          <label>Verified work email
            <input autocomplete="email" readonly type="email" :value="auth.userEmail">
          </label>

          <label>Phone number <span>*</span>

            <input
              v-model="form.phoneNumber"
              :aria-invalid="Boolean(fieldErrors.phoneNumber)"
              autocomplete="tel"
              maxlength="24"
              placeholder="+1 (555) 000-0000"
              required
              type="tel"
            >
            <small v-if="fieldErrors.phoneNumber" class="form-field-error">{{ fieldErrors.phoneNumber }}</small>
          </label>
        </div>
      </section>

      <section class="registration-section">
        <div class="section-title">
          <h2>Employment details</h2>
          <p>Required details are reviewed by a Northstar administrator.</p>
        </div>

        <div class="registration-grid">
          <label>Department <span>*</span>

            <select v-model="form.department" :aria-invalid="Boolean(fieldErrors.department)" :disabled="departmentLoading || departments.length === 0" required>
              <option disabled value="">{{ departmentLoading ? 'Loading departments…' : 'Choose a department' }}</option>
              <option v-for="department in departments" :key="department">{{ department }}</option>
            </select>
            <small v-if="fieldErrors.department || departmentError" class="form-field-error">{{ fieldErrors.department || departmentError }}</small>
          </label>

          <label>Job title <span>*</span>
            <input v-model="form.jobTitle" :aria-invalid="Boolean(fieldErrors.jobTitle)" maxlength="120" required>
            <small v-if="fieldErrors.jobTitle" class="form-field-error">{{ fieldErrors.jobTitle }}</small>
          </label>

          <label>Employment type <span>*</span>

            <select v-model="form.employmentType" :aria-invalid="Boolean(fieldErrors.employmentType)" required>
              <option disabled value="">Choose employment type</option>
              <option v-for="type in employmentTypes" :key="type">{{ type }}</option>
            </select>
            <small v-if="fieldErrors.employmentType" class="form-field-error">{{ fieldErrors.employmentType }}</small>
          </label>

          <label>Employee ID <span v-if="isCorrectionRequired('employee_id')">*</span>
            <input v-model="form.employeeId" :aria-invalid="Boolean(fieldErrors.employee_id)" :required="isCorrectionRequired('employee_id')" maxlength="80" placeholder="Optional">
            <small v-if="fieldErrors.employee_id" class="form-field-error">{{ fieldErrors.employee_id }}</small>
          </label>

          <label>Office location or branch <span>*</span>
            <input v-model="form.officeLocation" :aria-invalid="Boolean(fieldErrors.officeLocation)" maxlength="120" required>
            <small v-if="fieldErrors.officeLocation" class="form-field-error">{{ fieldErrors.officeLocation }}</small>
          </label>

          <label>Date of joining <span v-if="isCorrectionRequired('date_of_joining')">*</span>
            <input v-model="form.dateOfJoining" :aria-invalid="Boolean(fieldErrors.dateOfJoining || fieldErrors.date_of_joining)" :max="latestJoiningDate" :required="isCorrectionRequired('date_of_joining')" type="date">
            <small v-if="fieldErrors.dateOfJoining || fieldErrors.date_of_joining" class="form-field-error">{{ fieldErrors.dateOfJoining || fieldErrors.date_of_joining }}</small>
          </label>

          <label>Manager's name <span v-if="isCorrectionRequired('manager_name')">*</span>
            <input v-model="form.managerName" :aria-invalid="Boolean(fieldErrors.manager_name)" :required="isCorrectionRequired('manager_name')" maxlength="120">
            <small v-if="fieldErrors.manager_name" class="form-field-error">{{ fieldErrors.manager_name }}</small>
          </label>

          <label>Profile photo
            <input accept="image/*" :disabled="saving || photoValidating" type="file" @change="selectPhoto">
            <small>{{ photoValidating ? 'Checking image type and content…' : 'Optional · Supported image formats up to 1 MB' }}</small>
          </label>
        </div>

        <fieldset v-if="photo" class="photo-choice">
          <legend>Would you like to use this photo as your Northstar profile picture?</legend>
          <label><input v-model="photoChoice" :value="true" type="radio"> Yes, use this photo as my profile picture.</label>
          <label><input v-model="photoChoice" :value="false" type="radio"> No, I do not want to use this photo as my profile picture.</label>
        </fieldset>

        <label class="bio-field">Short introduction <span v-if="isCorrectionRequired('bio')">*</span>
          <textarea v-model="form.bio" :aria-invalid="Boolean(fieldErrors.bio)" :required="isCorrectionRequired('bio')" maxlength="500" placeholder="Share a little about your role or experience." rows="4" />
          <small v-if="fieldErrors.bio" class="form-field-error">{{ fieldErrors.bio }}</small>
        </label>
      </section>

      <p v-if="error" class="form-error" role="alert">{{ error }}</p>

      <div class="form-actions">
        <button class="primary-action" :disabled="saving || photoValidating || departmentLoading" type="submit">
          {{ saving ? 'Submitting registration…' : 'Submit for approval' }}
          <v-icon v-if="saving" class="loading-icon" icon="mdi-loading" size="16" />
          <v-icon v-else icon="mdi-arrow-right" size="16" />
        </button>
      </div>
    </form>
  </main>
</template>

<style scoped>
.registration-page { max-width: 940px; margin: 0 auto; }
.photo-choice { display: grid; gap: 10px; border: 1px solid var(--ns-border-dce4d9, #dce4d9); padding: 14px; color: var(--ns-text-53665a, #53665a); font-size: 10px; }
.correction-notice { margin-bottom: 16px; padding: 16px; color: var(--ns-text-primary); }
.correction-notice p { margin: 7px 0 0; font-size: 11px; line-height: 1.6; }
.correction-notice strong { font-size: 12px; }
.photo-choice legend { padding: 0 5px; font-weight: 700; }
.photo-choice label { display: flex; align-items: center; gap: 8px; }
.registration-form { display: grid; gap: 25px; padding: clamp(18px, 4vw, 30px); }
.registration-section + .registration-section { border-top: 1px solid var(--ns-border-e8ede5, #e8ede5); padding-top: 23px; }
.section-title { margin-bottom: 15px; }
.section-title h2 { margin: 0; color: var(--ns-text-18352d, #18352d); font-size: 15px; }
.section-title p { margin: 5px 0 0; color: var(--ns-text-829187, #829187); font-size: 10px; line-height: 1.6; }
.registration-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 15px; }
.registration-grid label, .bio-field { display: grid; align-content: start; gap: 7px; color: var(--ns-text-53665a, #53665a); font-size: 10px; font-weight: 700; }
.registration-grid label > span { color: var(--ns-text-d35f46, #d35f46); }
.registration-grid .form-field-error { color: var(--ns-danger-text); font-size: 9px; font-weight: 500; line-height: 1.5; }
.registration-grid [aria-invalid="true"] { border-color: var(--ns-danger-text); }
.registration-grid input, .registration-grid select, .bio-field textarea {
  width: 100%; min-height: 40px; border: 1px solid var(--ns-border-dce4d9, #dce4d9); border-radius: 0;
  padding: 9px 11px; background: var(--ns-bg-fbfcf9, #fbfcf9); color: var(--ns-text-18352d, #18352d); font: 11px "Manrope", sans-serif;
}
.registration-grid input[readonly] { background: var(--ns-bg-f1f4ee, #f1f4ee); color: var(--ns-text-78877e, #78877e); }
.registration-grid input[type="file"] { padding: 7px; }
.registration-grid label small { color: var(--ns-text-8b9990, #8b9990); font-size: 8px; font-weight: 400; }
.bio-field textarea { resize: vertical; line-height: 1.6; }
.form-error { margin: 0; color: var(--ns-text-a34c39, #a34c39); font-size: 10px; }
.form-actions { display: flex; justify-content: flex-end; }
.primary-action:disabled { cursor: wait; opacity: .65; }
.registration-form { border-radius: 16px; box-shadow: 0 12px 34px rgb(15 23 42 / 6%); }
.registration-grid input, .registration-grid select, .bio-field textarea {
  border-radius: 8px;
  background: var(--ns-surface-raised);
  color: var(--ns-text-primary);
}
.registration-grid input:focus, .registration-grid select:focus, .bio-field textarea:focus {
  border-color: var(--ns-primary);
  outline: 3px solid color-mix(in srgb, var(--ns-primary) 18%, transparent);
  outline-offset: 1px;
}
.registration-grid input[readonly] { background: var(--ns-surface-raised); }
.registration-grid label > span { color: var(--ns-primary); }
.primary-action:focus-visible { outline: 3px solid var(--ns-blue-border); outline-offset: 2px; }
.loading-icon { animation: rotate 1s linear infinite; }
@keyframes rotate { to { transform: rotate(360deg); } }
@media (max-width: 620px) { .registration-grid { grid-template-columns: 1fr; } }
@media (prefers-reduced-motion: reduce) { .loading-icon { animation: none; } }
</style>
