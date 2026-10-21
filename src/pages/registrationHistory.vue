<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue'
  import { useAuthStore } from '@/stores/auth'
  import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

  type RegistrationRejection = {
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
    correction_fields: string[]
  }

  const auth = useAuthStore()
  const records = ref<RegistrationRejection[]>([])
  const loading = ref(false)
  const error = ref('')
  const currentStatus = computed(() => {
    if (auth.profile.approvalStatus === 'approved' && auth.profile.status === 'active') return 'Approved'
    if (auth.profile.approvalStatus === 'rejected') return 'Needs correction'
    if (auth.profile.approvalStatus === 'pending') return 'Awaiting review'
    return auth.profile.approvalStatus || 'Unavailable'
  })

  const correctionLabels: Record<string, string> = {
    first_name: 'First name',
    last_name: 'Last name',
    phone_number: 'Phone number',
    department: 'Department',
    job_title: 'Job title',
    employee_id: 'Employee ID',
    employment_type: 'Employment type',
    office_location: 'Office location',
    date_of_joining: 'Date of joining',
    manager_name: 'Manager\'s name',
    bio: 'Introduction',
  }

  async function loadHistory () {
    if (loading.value) return
    if (!isSupabaseConfigured || !supabase || !auth.userId) {
      error.value = 'Sign in to view your registration history.'
      records.value = []
      return
    }
    loading.value = true
    error.value = ''
    try {
      const { data, error: historyError } = await supabase.rpc('northstar_list_my_employee_rejection_history_with_corrections')
      if (historyError) {
        error.value = `Could not load registration history: ${historyError.message}`
        console.error(error.value, historyError)
      } else {
        records.value = data ?? []
      }
    } catch (historyError) {
      error.value = 'Could not load registration history. Please try again.'
      console.error(error.value, historyError)
    } finally {
      loading.value = false
    }
  }

  async function refreshStatus () {
    await auth.refreshProfile()
    if (auth.errorMessage) error.value = auth.errorMessage
  }

  function formatDate (value: string) {
    const date = new Date(value)
    return Number.isNaN(date.getTime())
      ? 'Date unavailable'
      : new Intl.DateTimeFormat(undefined, { dateStyle: 'long', timeStyle: 'short' }).format(date)
  }

  onMounted(() => {
    void refreshStatus()
    void loadHistory()
  })
</script>

<template>
  <main class="registration-history-page">
    <header class="page-heading">
      <div>
        <p class="eyebrow">EMPLOYEE ONBOARDING</p>
        <h1>Registration history</h1>
        <p>Review the registration decisions Northstar has recorded for your account.</p>
      </div>

      <button class="secondary-action" :disabled="loading" type="button" @click="loadHistory">
        {{ loading ? 'Refreshing…' : 'Refresh history' }}
      </button>
    </header>

    <section aria-labelledby="current-status-title" class="history-status surface-card">
      <div>
        <p class="eyebrow">CURRENT REGISTRATION</p>
        <h2 id="current-status-title">{{ currentStatus }}</h2>

        <p v-if="auth.profile.approvalStatus === 'approved' && auth.profile.status === 'active'">
          Your employee workspace is active. Earlier rejection events remain in the history below.
        </p>

        <p v-else-if="auth.profile.approvalStatus === 'rejected'">
          Correct the requested fields and resubmit your registration for review.
        </p>

        <p v-else>
          Registration history records rejection events. Current approval status is shown separately above.
        </p>
      </div>

      <v-icon
        aria-hidden="true"
        :color="auth.profile.approvalStatus === 'approved' ? 'success' : auth.profile.approvalStatus === 'rejected' ? 'error' : 'primary'"
        :icon="auth.profile.approvalStatus === 'approved' ? 'mdi-check-circle-outline' : auth.profile.approvalStatus === 'rejected' ? 'mdi-alert-circle-outline' : 'mdi-clock-outline'"
        size="32"
      />
    </section>

    <section aria-labelledby="history-events-title" class="history-events surface-card">
      <div class="history-section-heading">
        <div>
          <p class="eyebrow">PERMANENT AUDIT EVENTS</p>
          <h2 id="history-events-title">Rejection records</h2>
        </div>

        <span class="event-count">{{ records.length }} {{ records.length === 1 ? 'event' : 'events' }}</span>
      </div>

      <p v-if="error" class="history-error" role="alert">{{ error }}</p>
      <p v-else-if="loading" class="history-empty" role="status">Loading your registration history…</p>

      <div v-else-if="records.length > 0" class="history-event-list">
        <article v-for="record in records" :key="record.id" class="history-event">
          <div class="event-heading">
            <span class="event-icon"><v-icon icon="mdi-file-alert-outline" size="20" /></span>

            <div>
              <h3>Registration not approved</h3>
              <time :datetime="record.rejected_at">{{ formatDate(record.rejected_at) }}</time>
            </div>

            <span class="event-status">Rejected</span>
          </div>

          <dl class="event-details">
            <div><dt>Employee</dt><dd>{{ record.employee_name || 'Name unavailable in record' }}</dd></div>
            <div><dt>Employee number</dt><dd>{{ record.employee_number || 'Not recorded' }}</dd></div>
            <div><dt>Reviewed by</dt><dd>{{ record.rejected_by_email || 'Not recorded' }}</dd></div>
          </dl>

          <div class="event-reason"><strong>Reason provided</strong><p>{{ record.rejection_reason }}</p></div>

          <div class="event-corrections">
            <strong>Fields requested for correction</strong>

            <ul v-if="record.correction_fields?.length">
              <li v-for="field in record.correction_fields" :key="field">{{ correctionLabels[field] ?? field }}</li>
            </ul>

            <p v-else>No correction fields were recorded for this historical event.</p>
          </div>
        </article>
      </div>

      <div v-else class="history-empty-state">
        <v-icon aria-hidden="true" icon="mdi-timeline-clock-outline" size="32" />
        <h3>No rejection events recorded</h3>
        <p>Northstar currently has no rejection history for your account. This page does not invent submission or approval events that are not stored in the audit history.</p>
      </div>
    </section>

    <footer class="history-actions">
      <router-link v-if="auth.profile.approvalStatus === 'rejected'" class="primary-action" to="/employee-registration">
        Correct registration
      </router-link>

      <router-link v-else-if="auth.profile.approvalStatus === 'approved' && auth.profile.status === 'active'" class="primary-action" to="/overview">
        Open employee workspace
      </router-link>

      <router-link v-else class="secondary-action" to="/pending-approval">View approval status</router-link>
      <button class="secondary-action" type="button" @click="refreshStatus">Refresh current status</button>
    </footer>
  </main>
</template>

<style scoped>
.registration-history-page { color: var(--ns-text-primary); }
.history-status, .history-events { border: 1px solid var(--ns-border); border-radius: 14px; background: var(--ns-surface); }
.history-status { display: flex; align-items: center; justify-content: space-between; gap: 20px; margin-bottom: 18px; padding: 20px 22px; }
.history-status .eyebrow, .history-section-heading .eyebrow { margin: 0 0 6px; color: var(--ns-text-secondary); font-size: 9px; letter-spacing: 1.1px; }
.history-status h2, .history-section-heading h2 { margin: 0; color: var(--ns-text-primary); font-size: 17px; }
.history-status p:last-child { margin: 7px 0 0; color: var(--ns-text-secondary); font-size: 11px; line-height: 1.6; }
.history-events { padding: 20px 22px; }
.history-section-heading { display: flex; align-items: center; justify-content: space-between; gap: 14px; margin-bottom: 16px; }
.event-count { color: var(--ns-text-secondary); font-size: 10px; }
.history-event-list { display: grid; gap: 14px; }
.history-event { border: 1px solid var(--ns-border); border-radius: 11px; padding: 16px; background: var(--ns-surface-raised); }
.event-heading { display: flex; align-items: center; gap: 11px; }
.event-icon { display: grid; width: 38px; height: 38px; flex: 0 0 38px; place-items: center; border-radius: 10px; background: color-mix(in srgb, var(--ns-danger-text) 12%, var(--ns-surface)); color: var(--ns-danger-text); }
.event-heading h3 { margin: 0 0 4px; color: var(--ns-text-primary); font-size: 12px; }
.event-heading time { color: var(--ns-text-secondary); font-size: 10px; }
.event-status { margin-left: auto; border-radius: 999px; padding: 5px 9px; background: color-mix(in srgb, var(--ns-danger-text) 10%, var(--ns-surface)); color: var(--ns-danger-text); font-size: 9px; font-weight: 700; }
.event-details { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin: 16px 0; }
.event-details div { min-width: 0; }
.event-details dt, .event-reason strong, .event-corrections > strong { color: var(--ns-text-secondary); font-size: 9px; }
.event-details dd { margin: 4px 0 0; color: var(--ns-text-primary); font-size: 10px; overflow-wrap: anywhere; }
.event-reason, .event-corrections { border-top: 1px solid var(--ns-border); padding-top: 12px; }
.event-reason p, .event-corrections p { margin: 6px 0 0; color: var(--ns-text-primary); font-size: 11px; line-height: 1.6; white-space: pre-wrap; }
.event-corrections { margin-top: 12px; }
.event-corrections ul { display: flex; flex-wrap: wrap; gap: 7px; margin: 9px 0 0; padding: 0; list-style: none; }
.event-corrections li { border: 1px solid var(--ns-blue-border); border-radius: 999px; padding: 5px 9px; background: var(--ns-blue-soft); color: var(--ns-text-primary); font-size: 9px; }
.history-empty, .history-error { color: var(--ns-text-secondary); font-size: 11px; }
.history-error { color: var(--ns-danger-text); }
.history-empty-state { display: grid; justify-items: center; gap: 8px; padding: 32px 12px; color: var(--ns-text-secondary); text-align: center; }
.history-empty-state h3 { margin: 2px 0 0; color: var(--ns-text-primary); font-size: 13px; }
.history-empty-state p { max-width: 570px; margin: 0; font-size: 10px; line-height: 1.6; }
.history-actions { display: flex; flex-wrap: wrap; gap: 9px; margin-top: 16px; }
@media (max-width: 640px) { .history-status, .history-events { padding: 16px; } .event-details { grid-template-columns: 1fr; gap: 9px; } .event-heading { align-items: flex-start; } .event-status { align-self: center; } }
</style>
