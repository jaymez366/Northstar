<script setup lang="ts">
  import { computed, onMounted, onUnmounted, ref } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useAuthStore } from '@/stores/auth'
  import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

  const auth = useAuthStore()
  const route = useRoute()
  const router = useRouter()
  const checking = ref(false)
  const error = ref('')
  const approvedNotice = ref(false)
  const showSubmissionSuccess = ref(false)
  const viewingSubmittedDetails = ref(false)
  const submittedPhotoUrl = ref('')
  const photoUnavailable = ref(false)
  type RejectionHistoryRecord = {
    id: string
    employee_id: string
    employee_number: string | null
    employee_name: string
    employee_email: string
    rejection_reason: string
    rejected_by_email: string
    rejected_at: string
    registration_snapshot_id: string | null
    status_at_event: string
    current_approval_status: string
  }
  const rejectionHistory = ref<RejectionHistoryRecord[]>([])
  const rejectionHistoryLoading = ref(false)
  const rejectionHistoryError = ref('')
  const isHistoryRoute = computed(() => route.path === '/rejection-history')
  let statusRefreshTimer: number | undefined

  onMounted(() => {
    showSubmissionSuccess.value = auth.registrationSubmissionSucceeded
    auth.registrationSubmissionSucceeded = false
    void loadSavedRegistrationDetails()
    void loadRejectionHistory()
    statusRefreshTimer = window.setInterval(() => {
      void checkStatus()
    }, 30_000)
  })

  async function loadSavedRegistrationDetails () {
    await auth.refreshProfile()
    if (!isSupabaseConfigured || !supabase || !auth.userId) return

    const { data: photoPath, error: photoPathError } = await supabase.rpc('northstar_get_my_registration_photo')
    if (photoPathError) {
      console.error('Could not load the saved registration photo path', photoPathError)
      return
    }
    if (typeof photoPath !== 'string') return

    const { data, error: signedUrlError } = await supabase.storage
      .from('profile-avatars')
      .createSignedUrl(photoPath, 3600)
    if (signedUrlError) {
      console.error('Could not create a signed URL for the saved registration photo', signedUrlError)
      return
    }
    submittedPhotoUrl.value = data.signedUrl
  }

  onUnmounted(() => {
    if (statusRefreshTimer !== undefined) {
      window.clearInterval(statusRefreshTimer)
    }
  })

  async function checkStatus () {
    if (checking.value) return
    checking.value = true
    error.value = ''
    try {
      await auth.refreshProfile()
      if (auth.canAccessEmployeeWorkspace) {
        approvedNotice.value = true
        if (!isHistoryRoute.value) {
          await new Promise(resolve => window.setTimeout(resolve, 1800))
          await router.replace('/overview')
        }
      } else if (auth.profile.registrationCompleted) {
        if (auth.errorMessage) {
          error.value = auth.errorMessage
        }
      } else {
        await router.replace('/employee-registration')
      }
    } finally {
      checking.value = false
    }
  }

  async function loadRejectionHistory () {
    rejectionHistoryLoading.value = true
    rejectionHistoryError.value = ''
    if (!isSupabaseConfigured || !supabase || !auth.userId) {
      rejectionHistoryError.value = 'Rejection history requires your signed-in Northstar account.'
      rejectionHistoryLoading.value = false
      return
    }

    try {
      const { data, error: historyError } = await supabase.rpc('northstar_list_my_employee_rejection_history')
      if (historyError) {
        rejectionHistoryError.value = `Could not load your rejection history: ${historyError.message}`
        console.error(rejectionHistoryError.value, historyError)
      } else {
        rejectionHistory.value = data ?? []
      }
    } catch (historyError) {
      rejectionHistoryError.value = 'Could not load your rejection history. Please try again.'
      console.error(rejectionHistoryError.value, historyError)
    } finally {
      rejectionHistoryLoading.value = false
    }
  }

  function formatRejectionDate (value: string) {
    const date = new Date(value)
    return Number.isNaN(date.getTime())
      ? 'Date unavailable'
      : new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(date)
  }

  async function signOut () {
    if (await auth.logout()) {
      await router.replace('/login')
    } else {
      error.value = auth.errorMessage
    }
  }
</script>

<template>
  <main class="approval-page">
    <section v-if="!viewingSubmittedDetails" class="approval-card surface-card">
      <span class="approval-icon"><v-icon icon="mdi-account-clock-outline" size="25" /></span>
      <p class="eyebrow">{{ isHistoryRoute ? 'REGISTRATION HISTORY' : 'REGISTRATION RECEIVED' }}</p>
      <h1 v-if="isHistoryRoute">Your registration<br><em>history.</em></h1>
      <h1 v-else>You're almost<br><em>in the Northstar.</em></h1>

      <p class="approval-copy">
        <template v-if="approvedNotice">
          Congratulations! Your employee registration has been approved. You can now access Northstar.
        </template>

        <template v-else-if="showSubmissionSuccess">
          Registration submitted successfully! Your profile is awaiting administrator review.
        </template>

        <template v-else-if="auth.profile.approvalStatus === 'rejected'">
          Your employee registration was not approved. Please review the administrator's reason below and update your registration if needed.
        </template>

        <template v-else-if="auth.profile.approvalStatus === 'approved' && auth.profile.status !== 'active'">
          Your registration is approved, but your employee account is not active yet. Contact the Northstar administrator for assistance.
        </template>

        <template v-else-if="auth.profile.approvalStatus === 'approved' && auth.profile.status === 'active'">
          Your registration is approved and your employee workspace is active. Previous rejection records remain listed below.
        </template>

        <template v-else>
          Your email is verified and your employee details have been submitted.
          Workspace access will be enabled after an administrator reviews your registration.
        </template>
      </p>

      <p v-if="auth.profile.approvalStatus === 'rejected' && auth.profile.rejectionReason" class="rejection-copy">
        <strong>Reason:</strong> {{ auth.profile.rejectionReason }}
      </p>

      <p class="approval-state" :class="{ rejected: auth.profile.approvalStatus === 'rejected' }">
        <i /> {{ approvedNotice || (auth.profile.approvalStatus === 'approved' && auth.profile.status === 'active') ? 'Registration approved' : (auth.profile.approvalStatus === 'rejected' ? 'Registration not approved' : (auth.profile.approvalStatus === 'approved' ? 'Account inactive' : 'Awaiting administrator approval')) }}
      </p>

      <section v-if="auth.profile.registrationCompleted" class="rejection-history" aria-labelledby="rejection-history-title">
        <div class="history-heading">
          <div>
            <p class="eyebrow">PERMANENT RECORDS</p>
            <h2 id="rejection-history-title">Previous rejection records</h2>
          </div>
          <button class="secondary-action" :disabled="rejectionHistoryLoading" type="button" @click="loadRejectionHistory">
            {{ rejectionHistoryLoading ? 'Loading…' : 'Refresh' }}
          </button>
        </div>
        <p v-if="rejectionHistoryError" class="approval-error" role="alert">{{ rejectionHistoryError }}</p>
        <p v-else-if="rejectionHistoryLoading" class="approval-copy" role="status">Loading your rejection history…</p>
        <p v-else-if="rejectionHistory.length === 0" class="approval-copy">No historical rejection records are available for your account.</p>
        <article v-for="record in rejectionHistory" v-else :key="record.id" class="rejection-history-record">
          <div class="history-record-meta">
            <strong>Rejected · {{ formatRejectionDate(record.rejected_at) }}</strong>
            <span>Employee ID: {{ record.employee_number || record.employee_id }}</span>
            <span v-if="record.rejected_by_email">Reviewed by {{ record.rejected_by_email }}</span>
          </div>
          <p><strong>Reason:</strong> {{ record.rejection_reason }}</p>
          <small>Current registration status: {{ record.current_approval_status }}</small>
        </article>
      </section>

      <p v-if="error" class="approval-error" role="alert">{{ error }}</p>

      <div class="approval-actions">
        <button class="primary-action" :disabled="checking" type="button" @click="checkStatus">
          {{ checking ? 'Checking…' : 'Check approval status' }}
          <v-icon icon="mdi-refresh" size="16" />
        </button>

        <router-link
          v-if="auth.profile.approvalStatus === 'rejected'"
          class="secondary-action resubmit-action"
          to="/employee-registration"
        >
          Update and resubmit registration
        </router-link>

        <button
          v-if="auth.profile.registrationCompleted"
          class="secondary-action"
          type="button"
          @click="viewingSubmittedDetails = true"
        >
          View Submitted Details
        </button>

        <button class="secondary-action" type="button" @click="signOut">Sign out</button>
      </div>
    </section>

    <section v-else class="approval-card details-card surface-card">
      <p class="eyebrow">EMPLOYEE REGISTRATION</p>
      <h1>Submitted<br><em>details</em></h1>
      <p class="approval-copy">These are the registration details currently saved to your Northstar profile.</p>

      <div class="submitted-details">
        <div v-if="(submittedPhotoUrl || auth.profile.photoUrl) && !photoUnavailable" class="submitted-photo-wrap">
          <img :src="submittedPhotoUrl || auth.profile.photoUrl" alt="Your saved registration photo" @error="photoUnavailable = true">
        </div>
        <p v-else class="submitted-photo-placeholder"><v-icon icon="mdi-account-circle-outline" size="30" />No profile photo saved</p>

        <dl class="submitted-detail-list">
          <div><dt>Name</dt><dd>{{ auth.profile.firstName }} {{ auth.profile.lastName }}</dd></div>
          <div><dt>Email address</dt><dd>{{ auth.userEmail }}</dd></div>
          <div><dt>Phone number</dt><dd>{{ auth.profile.phone }}</dd></div>
          <div><dt>Department</dt><dd>{{ auth.profile.department }}</dd></div>
          <div><dt>Job title</dt><dd>{{ auth.profile.jobTitle }}</dd></div>
          <div v-if="auth.profile.employeeId"><dt>Employee ID</dt><dd>{{ auth.profile.employeeId }}</dd></div>
          <div v-if="auth.profile.employmentType"><dt>Employment type</dt><dd>{{ auth.profile.employmentType }}</dd></div>
          <div v-if="auth.profile.officeLocation"><dt>Office location</dt><dd>{{ auth.profile.officeLocation }}</dd></div>
          <div v-if="auth.profile.dateOfJoining"><dt>Date of joining</dt><dd>{{ auth.profile.dateOfJoining }}</dd></div>
          <div v-if="auth.profile.managerName"><dt>Manager</dt><dd>{{ auth.profile.managerName }}</dd></div>
          <div v-if="auth.profile.bio"><dt>Introduction</dt><dd>{{ auth.profile.bio }}</dd></div>
        </dl>
      </div>

      <p v-if="error" class="approval-error" role="alert">{{ error }}</p>
      <div class="approval-actions">
        <button class="primary-action" type="button" @click="viewingSubmittedDetails = false">
          Back to Pending Approval
        </button>
        <button class="secondary-action" type="button" @click="signOut">Sign out</button>
      </div>
    </section>
  </main>
</template>

<style scoped>
.approval-page { display: grid; min-height: 62vh; place-items: center; padding: 20px; }
.approval-card { width: min(100%, 550px); padding: clamp(24px, 5vw, 40px); }
.details-card { width: min(100%, 720px); }
.approval-icon { display: grid; width: 48px; height: 48px; place-items: center; background: var(--ns-bg-f8e8df, #f8e8df); color: var(--ns-text-b8583e, #b8583e); }
.eyebrow { margin: 23px 0 10px; color: var(--ns-text-758b7c, #758b7c); font: 9px "DM Mono", monospace; letter-spacing: 1.5px; }
h1 { margin: 0; color: var(--ns-text-18352d, #18352d); font-size: clamp(34px, 6vw, 48px); line-height: 1.03; letter-spacing: -2px; }
h1 em { color: var(--ns-text-e16b4c, #e16b4c); font-style: normal; }
.approval-copy { max-width: 410px; margin: 16px 0; color: var(--ns-text-718178, #718178); font-size: 11px; line-height: 1.8; }
.approval-state { display: flex; align-items: center; gap: 8px; color: var(--ns-text-9b7049, #9b7049); font-size: 10px; }
.approval-state i { width: 7px; height: 7px; border-radius: 50%; background: var(--ns-bg-d79354, #d79354); }
.approval-state.rejected { color: var(--ns-text-a34c39, #a34c39); }
.approval-state.rejected i { background: var(--ns-bg-b85138, #b85138); }
.approval-error { color: var(--ns-text-a34c39, #a34c39); font-size: 10px; }
.rejection-copy { border-left: 3px solid var(--ns-border-b85138, #b85138); padding: 10px 12px; background: var(--ns-bg-fff7f3, #fff7f3); color: var(--ns-text-843f31, #843f31); font-size: 11px; line-height: 1.7; white-space: pre-wrap; }
.approval-actions { display: flex; flex-wrap: wrap; gap: 9px; margin-top: 23px; }
.approval-actions button { min-height: 39px; font-size: 9px; }
.resubmit-action { display: inline-flex; min-height: 39px; align-items: center; text-decoration: none; }
.submitted-details { display: grid; grid-template-columns: 150px minmax(0, 1fr); gap: 20px; align-items: start; margin-top: 20px; }
.submitted-photo-wrap { display: grid; min-height: 150px; place-items: center; border: 1px solid var(--ns-border-e3e9dc, #e3e9dc); background: var(--ns-bg-f8f9f6, #f8f9f6); }
.submitted-photo-wrap img { display: block; width: 100%; height: 150px; object-fit: contain; }
.submitted-photo-placeholder { display: flex; min-height: 70px; align-items: center; gap: 8px; color: var(--ns-text-829187, #829187); font-size: 10px; }
.submitted-detail-list { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 11px 16px; margin: 0; }
.submitted-detail-list > div { min-width: 0; }
.submitted-detail-list dt { color: var(--ns-text-829187, #829187); font-size: 9px; }
.submitted-detail-list dd { margin: 3px 0 0; color: var(--ns-text-18352d, #18352d); font-size: 11px; overflow-wrap: anywhere; }
.rejection-history { margin-top: 24px; border-top: 1px solid var(--ns-border-e3e9dc, #e3e9dc); padding-top: 18px; }
.history-heading { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.history-heading .eyebrow { margin-top: 0; }
.history-heading h2 { margin: 0; color: var(--ns-text-18352d, #18352d); font-size: 17px; }
.rejection-history-record { margin-top: 12px; border: 1px solid var(--ns-border-e3e9dc, #e3e9dc); border-radius: 10px; padding: 13px; background: var(--ns-surface-raised); color: var(--ns-text-primary); }
.history-record-meta { display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: center; font-size: 10px; }
.history-record-meta span, .rejection-history-record small { color: var(--ns-text-secondary); font-size: 9px; }
.rejection-history-record p { margin: 10px 0; white-space: pre-wrap; font-size: 11px; line-height: 1.6; }
@media (max-width: 580px) { .submitted-details { grid-template-columns: 1fr; } .submitted-photo-wrap { width: min(100%, 170px); } .submitted-detail-list { grid-template-columns: 1fr; } }
</style>
