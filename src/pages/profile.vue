<script setup lang="ts">
  import { reactive, ref } from 'vue'
  import { useAuthStore } from '@/stores/auth'
  import { isSupabaseConfigured } from '../../lib/supabase.js'

  const auth = useAuthStore()
  const editing = ref(false)
  const saved = ref(false)
  const photoError = ref('')
  const photoUrl = ref(auth.profile.photoUrl ?? '')
  const form = reactive({
    firstName: auth.profile.firstName ?? auth.userFirstName,
    lastName: auth.profile.lastName ?? '',
    email: auth.userEmail,
    jobTitle: auth.profile.jobTitle ?? '',
    department: auth.profile.department ?? '',
    phone: auth.profile.phone ?? '',
  })

  async function saveProfile () {
    const savedProfile = await auth.saveProfile({
      firstName: form.firstName.trim(),
      lastName: form.lastName.trim(),
      jobTitle: form.jobTitle.trim(),
      department: form.department,
      phone: form.phone.trim(),
      photoUrl: photoUrl.value,
    })
    if (!savedProfile) {
      photoError.value = auth.errorMessage
      return
    }
    saved.value = true
    editing.value = false
    window.setTimeout(() => {
      saved.value = false
    }, 3000)
  }

  async function uploadPhoto (event: Event) {
    const file = (event.target as HTMLInputElement).files?.[0]
    if (!file) return
    photoError.value = ''

    if (!file.type.startsWith('image/')) {
      photoError.value = 'Choose an image file.'
      return
    }

    if (file.size > 1_000_000) {
      photoError.value = 'Choose an image smaller than 1 MB.'
      return
    }

    if (isSupabaseConfigured) {
      if (await auth.uploadAvatar(file)) {
        photoUrl.value = auth.profile.photoUrl
      } else {
        photoError.value = auth.errorMessage
      }
      return
    }

    const reader = new FileReader()
    reader.addEventListener('load', () => {
      if (typeof reader.result === 'string') photoUrl.value = reader.result
    })
    reader.addEventListener('error', () => {
      photoError.value = 'The photo could not be read. Please choose another image.'
    })
    reader.readAsDataURL(file)
  }
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">YOUR ACCOUNT</p><h1>Profile</h1><p>Keep your details current so colleagues know how to reach you.</p></div><button v-if="!editing" class="primary-action" @click="editing = true"><v-icon icon="mdi-pencil-outline" size="17" /> Edit profile</button></header>
    <p v-if="saved" class="success-note" role="status"><v-icon icon="mdi-check-circle-outline" size="17" /> Your profile has been saved.</p>

    <form class="profile-layout" @submit.prevent="saveProfile">
      <section class="profile-card surface-card">
        <div class="profile-avatar" :style="photoUrl ? { backgroundImage: `url(${photoUrl})` } : undefined">{{ !photoUrl ? `${(form.firstName || 'U').charAt(0).toUpperCase()}${(form.lastName || '').charAt(0).toUpperCase()}` : '' }}</div>
        <h2>{{ form.firstName }} {{ form.lastName }}</h2><p>{{ form.jobTitle || 'Northstar member' }}</p>
        <span class="profile-status"><i /> Active employee</span>
        <div class="profile-divider" />
        <small>PROFILE PHOTO</small>

        <label v-if="editing" class="secondary-action photo-button">
          <v-icon icon="mdi-camera-outline" size="16" /> Change photo
          <input accept="image/*" type="file" @change="uploadPhoto">
        </label>

        <p v-if="photoError" class="photo-error" role="alert">{{ photoError }}</p>
        <p v-else-if="!editing" class="photo-hint">Your initials appear until you add a photo.</p>
      </section>

      <section class="profile-form surface-card">
        <div class="form-section-heading"><div><h2>Personal information</h2><p>Details visible to people in your organization.</p></div><span v-if="editing" class="edit-label">EDITING</span></div>

        <div class="form-grid">
          <label>First name<input v-model="form.firstName" :readonly="!editing" required></label>
          <label>Last name<input v-model="form.lastName" :readonly="!editing"></label>
          <label>Email address<input v-model="form.email" readonly type="email"><small>Email is managed by your sign-in account.</small></label>
          <label>Phone number<input v-model="form.phone" placeholder="+1 (555) 000-0000" :readonly="!editing" type="tel"></label>
          <label>Job title<input v-model="form.jobTitle" placeholder="Your role" :readonly="!editing"></label>
          <label>Department<select v-model="form.department" :disabled="!editing || isSupabaseConfigured"><option value="">Select department</option><option v-for="name in ['People', 'Communications', 'Engineering', 'Finance', 'Operations', 'Customer Success', 'Security']" :key="name">{{ name }}</option></select></label>
        </div>

        <div v-if="editing" class="form-actions"><button class="secondary-action" type="button" @click="editing = false">Cancel</button><button class="primary-action" type="submit"><v-icon icon="mdi-content-save-outline" size="16" /> Save changes</button></div>
      </section>
    </form>
  </main>
</template>

<style scoped>
.success-note { display: flex; align-items: center; gap: 8px; margin: -10px 0 16px; color: #4b8058; font-size: 11px; }
.profile-layout { display: grid; grid-template-columns: 270px minmax(0, 1fr); align-items: start; gap: 15px; }
.profile-card { padding: 25px 20px; text-align: center; }
.profile-avatar { display: grid; width: 76px; height: 76px; margin: 0 auto; place-items: center; border: 5px solid #f2f5ed; border-radius: 50%; background: #dce8ba; color: #18352d; font-size: 23px; font-weight: 800; }
.profile-avatar[style*="background-image"] { background-position: center; background-size: cover; }
.profile-card h2 { margin: 13px 0 4px; color: #18352d; font-size: 16px; }
.profile-card > p { margin: 0; color: #718178; font-size: 10px; }
.profile-status { display: inline-flex; align-items: center; gap: 6px; margin-top: 13px; color: #66806f; font-size: 9px; }
.profile-status i { width: 6px; height: 6px; border-radius: 50%; background: #70a879; }
.profile-divider { height: 1px; margin: 20px 0 16px; background: #edf0e9; }
.profile-card > small, .edit-label { color: #829187; font: 8px "DM Mono", monospace; letter-spacing: 1px; }
.photo-button { width: 100%; margin-top: 9px; font-size: 9px; }
.photo-button input { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0, 0, 0, 0); }
.photo-error, .photo-hint { margin: 8px 0 0; color: #829187; font-size: 8px; }
.photo-error { color: #b85138; }
.profile-form { padding: 22px; }
.form-section-heading { display: flex; align-items: start; justify-content: space-between; margin-bottom: 19px; }
.form-section-heading h2 { margin: 0; color: #18352d; font-size: 15px; }
.form-section-heading p { margin: 5px 0 0; color: #829187; font-size: 10px; }
.form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 15px; }
.form-grid label { display: grid; gap: 7px; color: #52645a; font-size: 10px; font-weight: 700; }
.form-grid input, .form-grid select { width: 100%; min-height: 39px; border: 1px solid #dce4d8; border-radius: 0; padding: 0 11px; background: #fff; color: #18352d; font: 11px "Manrope", sans-serif; }
.form-grid input:read-only, .form-grid select:disabled { background: #f6f7f3; color: #718178; }
.form-grid label small { color: #94a097; font-size: 8px; font-weight: 400; }
.form-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 20px; }
@media (max-width: 760px) { .profile-layout { grid-template-columns: 1fr; } .form-grid { grid-template-columns: 1fr; } }
</style>
