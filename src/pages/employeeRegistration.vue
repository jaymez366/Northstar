<script setup lang="ts">
  import { reactive, ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'

  const auth = useAuthStore()
  const router = useRouter()
  const saving = ref(false)
  const error = ref('')
  const photo = ref<File | null>(null)
  const departments = [
    'Administration',
    'Human Resources',
    'Information Technology',
    'Finance and Accounting',
    'Marketing',
    'Sales',
    'Operations',
    'Customer Support',
    'Communications',
    'Other',
  ]
  const employmentTypes = ['Full-time', 'Part-time', 'Contract', 'Intern', 'Other']
  const form = reactive({
    firstName: auth.profile.firstName,
    lastName: auth.profile.lastName,
    phoneNumber: auth.profile.phone,
    department: auth.profile.department,
    jobTitle: auth.profile.jobTitle,
    employeeId: auth.profile.employeeId,
    employmentType: '',
    officeLocation: auth.profile.officeLocation,
    dateOfJoining: auth.profile.dateOfJoining,
    managerName: auth.profile.managerName,
    bio: auth.profile.bio,
  })
  const departmentOptions = [...new Set([...departments, auth.profile.department].filter(Boolean))]

  function validateForm () {
    if (!form.firstName.trim() || !form.lastName.trim() || !form.phoneNumber.trim()
      || !form.department || !form.jobTitle.trim() || !form.employmentType
      || !form.officeLocation.trim()) {
      return 'Complete all required fields before submitting.'
    }
    if (!/^\+?[\d\s().-]{7,20}$/.test(form.phoneNumber.trim())
      || form.phoneNumber.replace(/\D/g, '').length < 7) {
      return 'Enter a valid phone number with at least seven digits.'
    }
    return ''
  }

  async function submitRegistration () {
    error.value = validateForm()
    if (error.value || saving.value) return

    saving.value = true
    try {
      const saved = await auth.completeEmployeeRegistration({ ...form })
      if (!saved) {
        error.value = auth.errorMessage || 'Your registration could not be saved.'
        return
      }
      if (photo.value) {
        const uploaded = await auth.uploadAvatar(photo.value)
        if (!uploaded) {
          error.value = auth.errorMessage || 'Your profile photo could not be uploaded.'
          return
        }
      }
      await router.replace({ path: '/pending-approval', query: { submitted: 'true' } })
    } catch (submitError) {
      error.value = auth.errorMessage || 'Your registration could not be saved. Please try again.'
      console.error('Employee registration submission failed', submitError)
    } finally {
      saving.value = false
    }
  }

  function selectPhoto (event: Event) {
    const file = (event.target as HTMLInputElement).files?.[0]
    if (!file) return
    if (!file.type.startsWith('image/') || file.size > 1_000_000) {
      error.value = 'Choose an image file smaller than 1 MB.'
      return
    }
    photo.value = file
    error.value = ''
  }
</script>

<template>
  <main class="registration-page">
    <header class="page-heading">
      <div>
        <p class="eyebrow">EMPLOYEE ONBOARDING</p>
        <h1>Complete your registration</h1>
        <p>Provide your work details. An administrator will review your registration before workspace access is enabled.</p>
      </div>
    </header>

    <form class="registration-form surface-card" @submit.prevent="submitRegistration">
      <section class="registration-section">
        <div class="section-title">
          <h2>Personal details</h2>
          <p>Your verified Northstar account is used to identify your profile.</p>
        </div>

        <div class="registration-grid">
          <label>First name <span>*</span>
            <input v-model="form.firstName" autocomplete="given-name" maxlength="80" required>
          </label>

          <label>Last name <span>*</span>
            <input v-model="form.lastName" autocomplete="family-name" maxlength="80" required>
          </label>

          <label>Verified work email
            <input autocomplete="email" readonly type="email" :value="auth.userEmail">
          </label>

          <label>Phone number <span>*</span>

            <input
              v-model="form.phoneNumber"
              autocomplete="tel"
              maxlength="24"
              placeholder="+1 (555) 000-0000"
              required
              type="tel"
            >
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

            <select v-model="form.department" required>
              <option disabled value="">Choose a department</option>
              <option v-for="department in departmentOptions" :key="department">{{ department }}</option>
            </select>
          </label>

          <label>Job title <span>*</span>
            <input v-model="form.jobTitle" maxlength="120" required>
          </label>

          <label>Employment type <span>*</span>

            <select v-model="form.employmentType" required>
              <option disabled value="">Choose employment type</option>
              <option v-for="type in employmentTypes" :key="type">{{ type }}</option>
            </select>
          </label>

          <label>Employee ID
            <input v-model="form.employeeId" maxlength="80" placeholder="Optional">
          </label>

          <label>Office location or branch <span>*</span>
            <input v-model="form.officeLocation" maxlength="120" required>
          </label>

          <label>Date of joining
            <input v-model="form.dateOfJoining" :max="new Date().toISOString().slice(0, 10)" type="date">
          </label>

          <label>Manager's name
            <input v-model="form.managerName" maxlength="120">
          </label>

          <label>Profile photo
            <input accept="image/jpeg,image/png,image/webp" type="file" @change="selectPhoto">
            <small>Optional · JPEG, PNG, or WebP up to 1 MB</small>
          </label>
        </div>

        <label class="bio-field">Short introduction
          <textarea v-model="form.bio" maxlength="500" placeholder="Share a little about your role or experience." rows="4" />
        </label>
      </section>

      <p v-if="error" class="form-error" role="alert">{{ error }}</p>

      <div class="form-actions">
        <button class="primary-action" :disabled="saving" type="submit">
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
.registration-form { display: grid; gap: 25px; padding: clamp(18px, 4vw, 30px); }
.registration-section + .registration-section { border-top: 1px solid #e8ede5; padding-top: 23px; }
.section-title { margin-bottom: 15px; }
.section-title h2 { margin: 0; color: #18352d; font-size: 15px; }
.section-title p { margin: 5px 0 0; color: #829187; font-size: 10px; line-height: 1.6; }
.registration-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 15px; }
.registration-grid label, .bio-field { display: grid; align-content: start; gap: 7px; color: #53665a; font-size: 10px; font-weight: 700; }
.registration-grid label > span { color: #d35f46; }
.registration-grid input, .registration-grid select, .bio-field textarea {
  width: 100%; min-height: 40px; border: 1px solid #dce4d9; border-radius: 0;
  padding: 9px 11px; background: #fbfcf9; color: #18352d; font: 11px "Manrope", sans-serif;
}
.registration-grid input[readonly] { background: #f1f4ee; color: #78877e; }
.registration-grid input[type="file"] { padding: 7px; }
.registration-grid label small { color: #8b9990; font-size: 8px; font-weight: 400; }
.bio-field textarea { resize: vertical; line-height: 1.6; }
.form-error { margin: 0; color: #a34c39; font-size: 10px; }
.form-actions { display: flex; justify-content: flex-end; }
.primary-action:disabled { cursor: wait; opacity: .65; }
.loading-icon { animation: rotate 1s linear infinite; }
@keyframes rotate { to { transform: rotate(360deg); } }
@media (max-width: 620px) { .registration-grid { grid-template-columns: 1fr; } }
@media (prefers-reduced-motion: reduce) { .loading-icon { animation: none; } }
</style>
