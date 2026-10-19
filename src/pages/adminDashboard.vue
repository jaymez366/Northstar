<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

const workspace = useWorkspaceStore()
const auth = useAuthStore()
const route = useRoute()
const isUuid = (value: string | null | undefined): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
type EmployeeRegistrationRecord = {
  user_id: string
  first_name: string
  last_name: string
  email: string
  phone_number: string | null
  department: string | null
  job_title: string | null
  employee_id: string | null
  employment_type: string | null
  office_location: string | null
  date_of_joining: string | null
  manager_name: string | null
  bio: string | null
  registration_completed: boolean
  approval_status: 'pending' | 'approved' | 'rejected'
  employment_status: string
  email_verification_status: 'Verified' | 'Not Verified'
  email_verified_at: string | null
  account_created_at: string
  registration_submitted_at: string | null
  registration_snapshot_is_original: boolean
  rejection_reason: string | null
  current_email: string
  current_first_name: string
  current_last_name: string
  current_avatar_url: string | null
  current_phone_number: string | null
  current_department: string | null
  current_job_title: string | null
  current_employee_id: string | null
  current_employment_type: string | null
  current_office_location: string | null
  current_date_of_joining: string | null
  current_manager_name: string | null
  current_bio: string | null
}
const employeeRecords = ref<EmployeeRegistrationRecord[]>([])
const emailVerificationRecords = ref<{
  user_id: string
  first_name: string
  last_name: string
  email: string
  email_verification_status: 'Verified' | 'Not Verified'
  email_verified_at: string | null
  account_created_at: string
}[]>([])
type SupportInquiry = {
  id: string
  user_id: string
  email: string
  full_name: string
  topic: string
  status: string
  created_at: string
  updated_at: string
}
type SupportMessage = { id: string, sender_id: string, sender_name: string, content: string, created_at: string }
const supportInquiries = ref<SupportInquiry[]>([])
const selectedSupportInquiry = ref<SupportInquiry | null>(null)
const supportMessages = ref<SupportMessage[]>([])
const supportReply = ref('')
const supportLoading = ref(false)
const supportReplyLoading = ref(false)
const supportError = ref('')
const employeePhotoUrl = ref('')
const employeePhotoPreviewOpen = ref(false)
const employeePhotoLoading = ref(false)
const approvalsLoading = ref(false)
const approvalError = ref('')
const updatingEmployeeId = ref('')
const employeeFilter = ref<'pending' | 'approved' | 'rejected'>('pending')
const employeeTabs = [
  { value: 'pending', label: 'Pending' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
] as const
const registrationSearch = ref('')
const selectedEmployee = ref<EmployeeRegistrationRecord | null>(null)
const rejectEmployee = ref<EmployeeRegistrationRecord | null>(null)
const rejectionReason = ref('')
const rejectionDialogError = ref('')
const verificationRecordsLoading = ref(false)
const verificationRecordsError = ref('')
const filteredRegistrations = computed(() => employeeRecords.value
  .filter(employee => employee.approval_status === employeeFilter.value)
  .filter(employee => `${employee.first_name} ${employee.last_name} ${employee.email} ${employee.department ?? ''} ${employee.job_title ?? ''}`
    .toLowerCase()
    .includes(registrationSearch.value.trim().toLowerCase())))
async function loadEmployeeRecords() {
  if (!auth.isAdmin) {
    approvalError.value = 'Only the confirmed Northstar administrator account can access registration approvals.'
    return
  }
  if (!isSupabaseConfigured || !supabase) {
    approvalError.value = 'Employee approvals require a configured Northstar Supabase connection.'
    return
  }
  approvalsLoading.value = true
  approvalError.value = ''
  try {
    const { data, error } = await supabase.rpc('northstar_admin_list_employee_registrations')
    if (error) {
      approvalError.value = `Could not load employee registrations: ${error.message}`
      console.error(approvalError.value, error)
      return
    }
    employeeRecords.value = data ?? []
  } catch (error) {
    approvalError.value = 'Could not load employee registrations. Please try again.'
    console.error(approvalError.value, error)
  } finally {
    approvalsLoading.value = false
  }
}

async function loadEmailVerificationRecords() {
  if (!auth.isAdmin) {
    verificationRecordsError.value = 'Only the confirmed Northstar administrator account can access email verification records.'
    return
  }
  if (!isSupabaseConfigured || !supabase) {
    verificationRecordsError.value = 'Email verification records require a configured Northstar Supabase connection.'
    return
  }
  verificationRecordsLoading.value = true
  verificationRecordsError.value = ''
  try {
    const { data, error } = await supabase.rpc('northstar_admin_list_email_verification_status')
    if (error) {
      verificationRecordsError.value = `Could not load email verification records: ${error.message}`
      console.error(verificationRecordsError.value, error)
      return
    }
    emailVerificationRecords.value = data ?? []
  } catch (error) {
    verificationRecordsError.value = 'Could not load email verification records. Please try again.'
    console.error(verificationRecordsError.value, error)
  } finally {
    verificationRecordsLoading.value = false
  }
}

async function loadSupportInquiries() {
  if (!auth.isAdmin || !supabase) return
  supportLoading.value = true
  supportError.value = ''
  const { data, error } = await supabase.rpc('northstar_admin_list_support_inquiries')
  if (error) {
    supportError.value = `Could not load support inquiries: ${error.message}`
    console.error(supportError.value, error)
  } else {
    supportInquiries.value = data ?? []
  }
  supportLoading.value = false
}

async function openEmployeeDetails(employee: EmployeeRegistrationRecord) {
  selectedEmployee.value = employee
  employeePhotoUrl.value = ''
  employeePhotoPreviewOpen.value = false
  if (!supabase || !isUuid(employee.user_id)) return
  employeePhotoLoading.value = true
  try {
    const { data: submittedPath, error: photoError } = await supabase.rpc('northstar_admin_get_registration_photo', {
      p_user_id: employee.user_id,
    })
    if (photoError) console.error('Could not load submitted employee registration photo', photoError)
    const path = typeof submittedPath === 'string' ? submittedPath : employee.current_avatar_url
    if (path) {
      const { data, error } = await supabase.storage.from('profile-avatars').createSignedUrl(path, 3600)
      if (error) console.error('Could not create a signed URL for the employee photo', error)
      else employeePhotoUrl.value = data.signedUrl
    }
  } finally {
    employeePhotoLoading.value = false
  }
}

async function openSupportInquiry(inquiry: SupportInquiry) {
  selectedSupportInquiry.value = inquiry
  supportReply.value = ''
  supportMessages.value = []
  supportError.value = ''
  if (!isUuid(inquiry.id) || !supabase) return
  const { data, error } = await supabase.rpc('northstar_get_support_inquiry_messages', { p_inquiry_id: inquiry.id })
  if (error) {
    supportError.value = `Could not load inquiry messages: ${error.message}`
    console.error(supportError.value, error)
  } else {
    supportMessages.value = data ?? []
  }
}

async function sendSupportReply() {
  const inquiry = selectedSupportInquiry.value
  const content = supportReply.value.trim()
  if (!inquiry || !isUuid(inquiry.id) || !content || supportReplyLoading.value || !supabase) return
  supportReplyLoading.value = true
  supportError.value = ''
  const { error } = await supabase.rpc('northstar_admin_reply_support_inquiry', {
    p_inquiry_id: inquiry.id,
    p_message: content,
  })
  if (error) {
    supportError.value = `Could not send reply: ${error.message}`
    console.error(supportError.value, error)
  } else {
    supportReply.value = ''
    await openSupportInquiry(inquiry)
    await loadSupportInquiries()
  }
  supportReplyLoading.value = false
}

function formatRecordDate(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

function openRejectionDialog(employee: EmployeeRegistrationRecord) {
  rejectEmployee.value = employee
  rejectionReason.value = ''
  rejectionDialogError.value = ''
}

async function setEmployeeApproval(employee: EmployeeRegistrationRecord, approvalStatus: 'approved' | 'rejected') {
  if (!auth.isAdmin || !supabase || !isUuid(employee.user_id) || updatingEmployeeId.value) {
    approvalError.value = 'Only the confirmed Northstar administrator account can update registration approvals.'
    return
  }
  if (approvalStatus === 'rejected' && !rejectionReason.value.trim()) {
    rejectionDialogError.value = 'Enter a rejection reason before confirming.'
    return
  }
  updatingEmployeeId.value = employee.user_id
  approvalError.value = ''
  try {
    const { error } = await supabase.rpc('northstar_admin_update_employee_registration_status', {
      p_user_id: employee.user_id,
      p_approval_status: approvalStatus,
      p_rejection_reason: approvalStatus === 'rejected' ? rejectionReason.value.trim() : null,
    })
    if (error) {
      approvalError.value = `Could not update employee approval: ${error.message}`
      console.error(approvalError.value, error)
      return
    }
    rejectEmployee.value = null
    rejectionReason.value = ''
    await loadEmployeeRecords()
  } catch (error) {
    approvalError.value = 'Could not update employee approval. Please try again.'
    console.error(approvalError.value, error)
  } finally {
    updatingEmployeeId.value = ''
  }
}

onMounted(() => {
  void workspace.loadAnnouncements().then(error => {
    if (error) console.error('Could not load announcements for the admin dashboard', error)
  })
  void loadEmployeeRecords().then(() => {
    const registrationId = typeof route.query.registration === 'string' ? route.query.registration : ''
    if (!isUuid(registrationId)) return
    const registration = employeeRecords.value.find(employee => employee.user_id === registrationId)
    if (registration) void openEmployeeDetails(registration)
  })
  void loadEmailVerificationRecords()
  void loadSupportInquiries()
})
</script>

<template>
  <main>
    <header class="page-heading">
      <div>
        <p class="eyebrow">ADMINISTRATION</p>
        <h1>Admin dashboard</h1>
        <p>Organization activity and management shortcuts in one place.</p>
      </div>

      <span class="admin-badge"><v-icon icon="mdi-shield-check-outline" size="16" /> ADMIN WORKSPACE</span>
    </header>

    <section class="approval-panel surface-card">
      <div class="panel-heading">
        <div>
          <p class="eyebrow">EMPLOYEE ONBOARDING</p>
          <h2>Employee registrations</h2>
        </div>

        <button class="secondary-action" :disabled="approvalsLoading" type="button" @click="loadEmployeeRecords">
          {{ approvalsLoading ? 'Refreshing…' : 'Refresh' }}
        </button>
      </div>

      <div aria-label="Filter employee registrations by status" class="registration-tabs" role="tablist">
        <button v-for="tab in employeeTabs" :key="tab.value" :aria-selected="employeeFilter === tab.value"
          :class="{ selected: employeeFilter === tab.value }" role="tab" type="button"
          @click="employeeFilter = tab.value">
          {{ tab.label }}
          <span>{{employeeRecords.filter(employee => employee.approval_status === tab.value).length}}</span>
        </button>
      </div>

      <input v-model="registrationSearch"
        aria-label="Search employee registrations by name, email, department, or job title"
        class="field-control registration-search" placeholder="Search name, email, department, or job title"
        type="search">

      <p v-if="approvalError" class="approval-error" role="alert">{{ approvalError }}</p>
      <p v-else-if="approvalsLoading" class="approval-empty">Loading employee registrations…</p>

      <p v-else-if="filteredRegistrations.length === 0" class="approval-empty">
        {{ registrationSearch ? 'No registrations match your search.' : `No ${employeeFilter} employee registrations.`
        }}
      </p>

      <div v-else class="approval-list">
        <article v-for="employee in filteredRegistrations" :key="employee.user_id" class="approval-item">
          <div class="approval-details">
            <strong>{{ employee.first_name }} {{ employee.last_name }}</strong>
            <span>{{ employee.email }} · {{ employee.department || 'Department unavailable' }} · {{ employee.job_title
              || 'Job title unavailable' }}</span>

            <small>
              {{ employee.employment_type || 'Employment type unavailable' }} · {{ employee.office_location || 'Location unavailable' }}
              <template v-if="employee.employee_id"> · ID {{ employee.employee_id }}</template>
              <template v-if="employee.manager_name"> · Manager {{ employee.manager_name }}</template>
            </small>

            <small v-if="employee.rejection_reason" class="rejection-reason">
              Rejection reason: {{ employee.rejection_reason }}
            </small>
          </div>

          <div class="approval-actions">
            <button class="details-button" type="button" @click="openEmployeeDetails(employee)">View Details</button>

            <button v-if="employee.approval_status === 'pending'" class="approve-button"
              :disabled="Boolean(updatingEmployeeId)" type="button" @click="setEmployeeApproval(employee, 'approved')">
              <v-progress-circular
                v-if="updatingEmployeeId === employee.user_id && rejectEmployee?.user_id !== employee.user_id"
                aria-hidden="true" indeterminate size="14" width="2" />
              {{ updatingEmployeeId === employee.user_id && rejectEmployee?.user_id !== employee.user_id ? 'Approving…'
                :
              'Approve' }}
            </button>

            <button v-if="employee.approval_status === 'pending'" class="reject-button"
              :disabled="Boolean(updatingEmployeeId)" type="button"
              @click="openRejectionDialog(employee)">Reject</button>
          </div>
        </article>
      </div>
    </section>

    <v-dialog max-width="760" :model-value="Boolean(selectedEmployee)"
      @update:model-value="!$event && (selectedEmployee = null)">
      <v-card v-if="selectedEmployee" class="employee-detail-dialog">
        <v-card-title class="dialog-heading">
          <span>Employee registration details</span>
          <v-btn aria-label="Close employee details" icon="mdi-close" variant="text" @click="selectedEmployee = null" />
        </v-card-title>

        <v-card-text>
          <div class="employee-photo-wrap">
            <v-progress-circular v-if="employeePhotoLoading" aria-label="Loading employee photo" indeterminate size="22"
              width="2" />
            <button v-else-if="employeePhotoUrl" aria-label="View full employee profile photo"
              class="employee-detail-photo-button" type="button" @click="employeePhotoPreviewOpen = true">
              <img :src="employeePhotoUrl" alt="Employee profile photo" class="employee-detail-photo"
                @error="employeePhotoUrl = ''">
            </button>
            <span v-else class="employee-photo-placeholder"><v-icon icon="mdi-account-circle-outline" size="58" />No
              profile
              photo</span>
          </div>
          <div class="detail-summary">
            <strong>{{ selectedEmployee.first_name }} {{ selectedEmployee.last_name }}</strong>
            <span>{{ selectedEmployee.email }}</span>
            <span class="registration-status" :class="selectedEmployee.approval_status">{{
              selectedEmployee.approval_status
              }}</span>
          </div>

          <p v-if="selectedEmployee.rejection_reason" class="detail-rejection">
            <strong>Rejection reason:</strong> {{ selectedEmployee.rejection_reason }}
          </p>

          <div class="detail-grid">
            <section>
              <h3>{{ selectedEmployee.registration_snapshot_is_original ? 'Originally submitted' : 'Available profile snapshot' }}</h3>

              <dl>
                <div>
                  <dt>First name</dt>
                  <dd>{{ selectedEmployee.first_name || '—' }}</dd>
                </div>
                <div>
                  <dt>Last name</dt>
                  <dd>{{ selectedEmployee.last_name || '—' }}</dd>
                </div>
                <div>
                  <dt>Email</dt>
                  <dd>{{ selectedEmployee.email || '—' }}</dd>
                </div>
                <div>
                  <dt>Phone</dt>
                  <dd>{{ selectedEmployee.phone_number || '—' }}</dd>
                </div>
                <div>
                  <dt>Department</dt>
                  <dd>{{ selectedEmployee.department || '—' }}</dd>
                </div>
                <div>
                  <dt>Job title</dt>
                  <dd>{{ selectedEmployee.job_title || '—' }}</dd>
                </div>
                <div>
                  <dt>Employee ID</dt>
                  <dd>{{ selectedEmployee.employee_id || '—' }}</dd>
                </div>
                <div>
                  <dt>Employment type</dt>
                  <dd>{{ selectedEmployee.employment_type || '—' }}</dd>
                </div>
                <div>
                  <dt>Office location</dt>
                  <dd>{{ selectedEmployee.office_location || '—' }}</dd>
                </div>
                <div>
                  <dt>Date of joining</dt>
                  <dd>{{ selectedEmployee.date_of_joining || '—' }}</dd>
                </div>
                <div>
                  <dt>Manager</dt>
                  <dd>{{ selectedEmployee.manager_name || '—' }}</dd>
                </div>
                <div>
                  <dt>Registration complete</dt>
                  <dd>{{ selectedEmployee.registration_completed ? 'Yes' : 'No' }}</dd>
                </div>
                <div>
                  <dt>Email verified</dt>
                  <dd>{{ selectedEmployee.email_verification_status }}</dd>
                </div>
                <div>
                  <dt>Email verified at</dt>
                  <dd>{{ formatRecordDate(selectedEmployee.email_verified_at) }}</dd>
                </div>
                <div>
                  <dt>Account created</dt>
                  <dd>{{ formatRecordDate(selectedEmployee.account_created_at) }}</dd>
                </div>
                <div>
                  <dt>Submitted at</dt>
                  <dd>{{ formatRecordDate(selectedEmployee.registration_submitted_at) }}</dd>
                </div>
                <div class="detail-bio">
                  <dt>Bio</dt>
                  <dd>{{ selectedEmployee.bio || '—' }}</dd>
                </div>
              </dl>

              <p v-if="!selectedEmployee.registration_snapshot_is_original" class="snapshot-note">
                Historical submission values were not available when this feature was installed; these values are the
                earliest profile snapshot captured by the migration.
              </p>
            </section>

            <section>
              <h3>Current profile</h3>

              <dl>
                <div>
                  <dt>Email</dt>
                  <dd>{{ selectedEmployee.current_email || '—' }}</dd>
                </div>
                <div>
                  <dt>Phone</dt>
                  <dd>{{ selectedEmployee.current_phone_number || '—' }}</dd>
                </div>
                <div>
                  <dt>Department</dt>
                  <dd>{{ selectedEmployee.current_department || '—' }}</dd>
                </div>
                <div>
                  <dt>Job title</dt>
                  <dd>{{ selectedEmployee.current_job_title || '—' }}</dd>
                </div>
                <div>
                  <dt>Employee ID</dt>
                  <dd>{{ selectedEmployee.current_employee_id || '—' }}</dd>
                </div>
                <div>
                  <dt>Employment type</dt>
                  <dd>{{ selectedEmployee.current_employment_type || '—' }}</dd>
                </div>
                <div>
                  <dt>Office location</dt>
                  <dd>{{ selectedEmployee.current_office_location || '—' }}</dd>
                </div>
                <div>
                  <dt>Date of joining</dt>
                  <dd>{{ selectedEmployee.current_date_of_joining || '—' }}</dd>
                </div>
                <div>
                  <dt>Manager</dt>
                  <dd>{{ selectedEmployee.current_manager_name || '—' }}</dd>
                </div>
                <div class="detail-bio">
                  <dt>Bio</dt>
                  <dd>{{ selectedEmployee.current_bio || '—' }}</dd>
                </div>
              </dl>
            </section>
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>

    <v-dialog v-model="employeePhotoPreviewOpen" max-width="900">
      <v-card class="employee-photo-preview-card">
        <img :src="employeePhotoUrl" alt="Employee profile photo preview" class="employee-photo-preview">
      </v-card>
    </v-dialog>

    <v-dialog max-width="500" :model-value="Boolean(rejectEmployee)"
      @update:model-value="!$event && (rejectEmployee = null)">
      <v-card v-if="rejectEmployee" class="employee-detail-dialog">
        <v-card-title>Reject registration</v-card-title>

        <v-card-text>
          <p>Enter the reason that will be saved and shown to {{ rejectEmployee.first_name }} {{
            rejectEmployee.last_name
            }}.</p>
          <label class="rejection-label" for="rejection-reason">Rejection reason <span>*</span></label>
          <textarea id="rejection-reason" v-model="rejectionReason" maxlength="2000" rows="5" />
          <p v-if="rejectionDialogError" class="approval-error" role="alert">{{ rejectionDialogError }}</p>
        </v-card-text>

        <v-card-actions>
          <v-spacer />
          <v-btn :disabled="updatingEmployeeId === rejectEmployee.user_id" variant="text"
            @click="rejectEmployee = null">Cancel</v-btn>

          <v-btn color="error" :disabled="!rejectionReason.trim()"
            :loading="updatingEmployeeId === rejectEmployee.user_id"
            @click="setEmployeeApproval(rejectEmployee, 'rejected')">{{ updatingEmployeeId === rejectEmployee.user_id ?
              'Rejecting…' : 'Confirm rejection' }}</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <section class="approval-panel surface-card">
      <div class="panel-heading">
        <div>
          <p class="eyebrow">SUPABASE AUTHENTICATION</p>
          <h2>Email verification status</h2>
        </div>

        <button class="secondary-action" :disabled="verificationRecordsLoading" type="button"
          @click="loadEmailVerificationRecords">
          {{ verificationRecordsLoading ? 'Refreshing…' : 'Refresh' }}
        </button>
      </div>

      <p v-if="verificationRecordsError" class="approval-error" role="alert">{{ verificationRecordsError }}</p>
      <p v-else-if="verificationRecordsLoading" class="approval-empty">Loading email verification records…</p>
      <p v-else-if="emailVerificationRecords.length === 0" class="approval-empty">No user accounts were found.</p>

      <div v-else class="table-scroll verification-table">
        <table class="data-table">

          <caption class="sr-only">Employee email verification status from Supabase Authentication</caption>

          <thead>
            <tr>
              <th>NAME</th>
              <th>EMAIL</th>
              <th>EMAIL STATUS</th>
              <th>VERIFIED AT</th>
              <th>ACCOUNT CREATED</th>
            </tr>
          </thead>

          <tbody>
            <tr v-for="record in emailVerificationRecords" :key="record.user_id">
              <td>{{ `${record.first_name} ${record.last_name}`.trim() || '—' }}</td>

              <td>{{ record.email }}</td>

              <td>
                <span class="verification-status"
                  :class="{ verified: record.email_verification_status === 'Verified' }">
                  {{ record.email_verification_status }}
                </span>
              </td>

              <td>{{ formatRecordDate(record.email_verified_at) }}</td>

              <td>{{ formatRecordDate(record.account_created_at) }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="!verificationRecordsLoading && !verificationRecordsError && emailVerificationRecords.length > 0"
        class="verification-cards">
        <article v-for="record in emailVerificationRecords" :key="record.user_id" class="verification-card">
          <div class="verification-card-heading">
            <div>
              <strong>{{ `${record.first_name} ${record.last_name}`.trim() || 'Name unavailable' }}</strong>

              <a :href="`mailto:${record.email}`">{{ record.email }}</a>
            </div>

            <span class="verification-status" :class="{ verified: record.email_verification_status === 'Verified' }">
              {{ record.email_verification_status }}
            </span>
          </div>

          <dl>
            <div>
              <dt>Verified at</dt>

              <dd>{{ formatRecordDate(record.email_verified_at) }}</dd>
            </div>

            <div>
              <dt>Account created</dt>

              <dd>{{ formatRecordDate(record.account_created_at) }}</dd>
            </div>
          </dl>
        </article>
      </div>
    </section>

    <section class="approval-panel surface-card">
      <div class="panel-heading">
        <div>
          <p class="eyebrow">TALK TO AN EXPERT</p>
          <h2>Support inquiries</h2>
        </div>
        <button class="secondary-action" :disabled="supportLoading" type="button" @click="loadSupportInquiries">{{
          supportLoading ? 'Refreshing…' : 'Refresh' }}</button>
      </div>
      <p v-if="supportError" class="approval-error" role="alert">{{ supportError }}</p>
      <p v-else-if="supportLoading" class="approval-empty">Loading support inquiries…</p>
      <p v-else-if="supportInquiries.length === 0" class="approval-empty">No support inquiries have been submitted.</p>
      <div v-else class="approval-list">
        <article v-for="inquiry in supportInquiries" :key="inquiry.id" class="approval-item">
          <div class="approval-details"><strong>{{ inquiry.full_name }} · {{ inquiry.topic }}</strong><span>{{
              inquiry.email
              }} · {{ inquiry.status }}</span><small>{{ formatRecordDate(inquiry.created_at) }}</small></div>
          <button class="details-button" type="button" @click="openSupportInquiry(inquiry)">Open inquiry</button>
        </article>
      </div>
    </section>

    <v-dialog max-width="700" :model-value="Boolean(selectedSupportInquiry)"
      @update:model-value="!$event && (selectedSupportInquiry = null)">
      <v-card v-if="selectedSupportInquiry" class="employee-detail-dialog">
        <v-card-title class="dialog-heading"><span>Support inquiry · {{ selectedSupportInquiry.topic }}</span><v-btn
            aria-label="Close support inquiry" icon="mdi-close" variant="text"
            @click="selectedSupportInquiry = null" /></v-card-title>
        <v-card-text>
          <p><strong>{{ selectedSupportInquiry.full_name }}</strong> · {{ selectedSupportInquiry.email }}</p>
          <div class="support-message-list">
            <article v-for="message in supportMessages" :key="message.id" class="support-message"><strong>{{
              message.sender_name }}</strong>
              <p>{{ message.content }}</p><time>{{ formatRecordDate(message.created_at) }}</time>
            </article>
          </div>
          <label class="rejection-label" for="support-reply">Reply to employee</label>
          <textarea id="support-reply" v-model="supportReply" maxlength="5000" rows="4" />
          <p v-if="supportError" class="approval-error" role="alert">{{ supportError }}</p>
        </v-card-text>
        <v-card-actions><v-spacer /><v-btn color="primary" :disabled="!supportReply.trim() || supportReplyLoading"
            :loading="supportReplyLoading" @click="sendSupportReply">{{ supportReplyLoading ? 'Sending…' : 'Send reply'
            }}</v-btn></v-card-actions>
      </v-card>
    </v-dialog>

    <section class="admin-links">
      <router-link class="surface-card admin-link-card" to="/disaster-management">
        <span><v-icon icon="mdi-shield-alert-outline" /></span>
        <strong>Disaster management</strong>
        <small>Review incident reports and coordinate response</small>
        <v-icon class="link-arrow" icon="mdi-arrow-top-right" size="18" />
      </router-link>
      <router-link class="surface-card admin-link-card" to="/announcements">
        <span><v-icon icon="mdi-bullhorn-outline" /></span>
        <strong>Employee announcements</strong>
        <small>Read updates published by employees</small>
        <v-icon class="link-arrow" icon="mdi-arrow-top-right" size="18" />
      </router-link>
    </section>

    <p v-if="!isSupabaseConfigured" class="admin-note">Configure the Northstar Supabase project to load organization
      data.
    </p>
  </main>
</template>

<style scoped>
.admin-badge {
  display: flex;
  align-items: center;
  gap: 6px;
  color: #67816e;
  font: 8px "DM Mono", monospace;
  letter-spacing: 1px;
}

.approval-panel {
  margin: 14px 0;
  padding: 18px;
}

.approval-panel .panel-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.approval-panel h2 {
  margin: 4px 0 0;
  color: #18352d;
  font-size: 14px;
}

.approval-empty,
.approval-error {
  color: #829187;
  font-size: 10px;
}

.approval-error {
  color: #a34c39;
}

.registration-tabs {
  display: flex;
  gap: 6px;
  margin: 15px 0 10px;
  border-bottom: 1px solid #e8ede5;
}

.registration-tabs button {
  display: flex;
  align-items: center;
  gap: 7px;
  border: 0;
  border-bottom: 2px solid transparent;
  padding: 10px 12px;
  background: transparent;
  color: #718178;
  cursor: pointer;
  font: 700 10px "Manrope", sans-serif;
}

.registration-tabs button.selected {
  border-bottom-color: #e16b4c;
  color: #18352d;
}

.registration-tabs button span {
  display: grid;
  min-width: 19px;
  height: 19px;
  place-items: center;
  border-radius: 50%;
  background: #eef2e8;
  font-size: 9px;
}

.registration-search {
  width: min(100%, 420px);
  margin: 5px 0 10px;
}

.approval-list {
  display: grid;
  gap: 9px;
  margin-top: 14px;
}

.approval-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  border-top: 1px solid #edf0e9;
  padding-top: 12px;
}

.approval-details {
  display: grid;
  min-width: 0;
  gap: 5px;
}

.approval-details strong {
  color: #18352d;
  font-size: 11px;
}

.approval-details span,
.approval-details small {
  color: #718178;
  font-size: 9px;
  line-height: 1.5;
}

.approval-actions {
  display: flex;
  flex: 0 0 auto;
  gap: 6px;
}

.approval-actions button {
  border: 0;
  padding: 8px 10px;
  cursor: pointer;
  font: 700 9px "Manrope", sans-serif;
}

.approval-actions .details-button {
  border: 1px solid #dce4d9;
  background: #fff;
  color: #52645a;
}

.approve-button {
  background: #18352d;
  color: #f5f6ee;
}

.reject-button {
  background: #fae6de;
  color: #a44c38;
}

.approval-actions button:disabled {
  cursor: wait;
  opacity: .6;
}

.rejection-reason {
  color: #a34c39 !important;
}

.employee-detail-dialog {
  color: #18352d;
}

.dialog-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.detail-summary {
  display: grid;
  justify-items: start;
  gap: 5px;
  border-bottom: 1px solid #edf0e9;
  padding-bottom: 14px;
}

.employee-photo-wrap {
  display: grid;
  min-height: 58px;
  place-items: center start;
  margin-bottom: 12px;
}

.employee-detail-photo {
  display: block;
  width: min(100%, 180px);
  height: 180px;
  object-fit: contain;
  background: #f8f9f6;
}
.employee-detail-photo-button {
  border: 1px solid #e3e9dc;
  padding: 0;
  background: #f8f9f6;
  cursor: zoom-in;
}
.employee-photo-preview-card { display: grid; min-height: 240px; place-items: center; padding: 16px; background: #f8f9f6; }
.employee-photo-preview { display: block; max-width: 100%; max-height: 80vh; object-fit: contain; }

.employee-photo-placeholder {
  display: grid;
  justify-items: center;
  color: #829187;
  font-size: 10px;
}

.support-message-list {
  display: grid;
  max-height: 360px;
  gap: 10px;
  overflow-y: auto;
  margin: 14px 0;
}

.support-message {
  border: 1px solid #e3e9dc;
  padding: 11px;
  background: #f8f9f6;
}

.support-message strong {
  color: #18352d;
  font-size: 11px;
}

.support-message p {
  margin: 6px 0;
  color: #52645a;
  font-size: 11px;
  white-space: pre-wrap;
}

.support-message time {
  color: #829187;
  font-size: 9px;
}

.detail-summary strong {
  font-size: 17px;
}

.detail-summary>span:not(.registration-status) {
  color: #718178;
  font-size: 12px;
}

.registration-status {
  border-radius: 20px;
  padding: 4px 9px;
  background: #fff2df;
  color: #94651e;
  font-size: 10px;
  font-weight: 700;
  text-transform: capitalize;
}

.registration-status.approved {
  background: #e8f3e8;
  color: #4b8058;
}

.registration-status.rejected {
  background: #fae6de;
  color: #a44c38;
}

.detail-rejection {
  border-left: 3px solid #c65e46;
  margin: 14px 0 0;
  padding: 8px 11px;
  background: #fff8f5;
  color: #843f31;
  font-size: 12px;
  white-space: pre-wrap;
}

.detail-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 22px;
  padding-top: 16px;
}

.detail-grid h3 {
  margin: 0 0 9px;
  font-size: 12px;
}

.detail-grid dl {
  display: grid;
  gap: 9px;
  margin: 0;
}

.detail-grid dl>div {
  display: grid;
  gap: 3px;
}

.detail-grid dt {
  color: #829187;
  font-size: 10px;
}

.detail-grid dd {
  margin: 0;
  color: #334b3e;
  font-size: 11px;
  overflow-wrap: anywhere;
  white-space: pre-wrap;
}

.detail-grid .detail-bio {
  padding-top: 4px;
}

.snapshot-note {
  color: #829187;
  font-size: 10px;
  line-height: 1.5;
}

.rejection-label {
  display: block;
  margin-bottom: 6px;
  color: #53665a;
  font-size: 11px;
  font-weight: 700;
}

.rejection-label span {
  color: #d35f46;
}

.employee-detail-dialog textarea {
  width: 100%;
  border: 1px solid #dce4d9;
  padding: 10px;
  color: #18352d;
  font: 12px/1.5 "Manrope", sans-serif;
  resize: vertical;
}

.verification-status {
  color: #a34c39;
  font-weight: 700;
}

.verification-status.verified {
  color: #4b8058;
}

.verification-cards {
  display: none;
}

.verification-card {
  border-top: 1px solid #edf0e9;
  padding: 12px 0;
}

.verification-card-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.verification-card-heading>div {
  display: grid;
  min-width: 0;
  gap: 4px;
}

.verification-card-heading strong {
  color: #18352d;
  font-size: 11px;
}

.verification-card-heading a {
  overflow-wrap: anywhere;
  color: #718178;
  font-size: 10px;
}

.verification-card dl {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
  margin: 12px 0 0;
}

.verification-card dl>div {
  display: grid;
  gap: 4px;
}

.verification-card dt {
  color: #829187;
  font-size: 9px;
}

.verification-card dd {
  margin: 0;
  color: #52645a;
  font-size: 10px;
}

.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  clip-path: inset(50%);
}

.admin-stats {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 10px;
}

.admin-stats article {
  display: grid;
  min-height: 142px;
  justify-items: start;
  padding: 13px;
}

.admin-stats article>span {
  color: #6e866f;
}

.admin-stats article>small {
  margin-top: 8px;
  color: #829187;
  font: 8px "DM Mono", monospace;
}

.admin-stats article>strong {
  color: #18352d;
  font-size: 25px;
  letter-spacing: -1px;
}

.admin-stats article>a {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-top: 4px;
  color: #60796a;
  text-decoration: none;
  font-size: 8px;
}

.admin-columns {
  display: grid;
  grid-template-columns: 1.35fr .8fr;
  gap: 13px;
  margin-top: 17px;
}

.management-panel {
  min-width: 0;
  padding: 17px;
}

.panel-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 13px;
}

.panel-heading .eyebrow {
  margin: 0 0 5px;
}

.panel-heading h2 {
  margin: 0;
  color: #18352d;
  font-size: 14px;
}

.panel-heading>a {
  display: flex;
  align-items: center;
  gap: 4px;
  color: #60796a;
  text-decoration: none;
  font-size: 9px;
}

.table-scroll {
  overflow-x: auto;
}

.table-employee {
  display: flex;
  align-items: center;
  gap: 8px;
}

.table-employee i {
  display: grid;
  width: 27px;
  height: 27px;
  place-items: center;
  border-radius: 50%;
  color: #18352d;
  font-size: 7px;
  font-style: normal;
  font-weight: 800;
}

.table-employee>span {
  display: grid;
  gap: 3px;
}

.table-employee strong {
  color: #52645a;
  font-size: 9px;
}

.table-employee small {
  color: #829187;
  font-size: 8px;
}

.table-status {
  color: #829187;
  font-size: 9px;
}

.table-status.online {
  color: #5b8766;
}

.activity-list {
  display: grid;
}

.activity-list article {
  display: flex;
  gap: 10px;
  padding: 12px 0;
  border-top: 1px solid #edf0e9;
}

.activity-list article>span {
  display: grid;
  flex: 0 0 31px;
  width: 31px;
  height: 31px;
  place-items: center;
  background: #eef2e8;
  color: #6e866f;
}

.activity-list article>div {
  display: grid;
  gap: 5px;
}

.activity-list strong {
  color: #52645a;
  font-size: 9px;
  line-height: 1.5;
}

.activity-list small {
  color: #829187;
  font-size: 8px;
}

.no-activity {
  color: #829187;
  font-size: 10px;
}

.admin-links {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 11px;
  margin-top: 13px;
}

.admin-link-card {
  position: relative;
  display: grid;
  grid-template-columns: 38px 1fr;
  gap: 5px 11px;
  padding: 14px;
  color: #18352d;
  text-decoration: none;
}

.admin-link-card>span {
  grid-row: span 2;
  display: grid;
  width: 38px;
  height: 38px;
  place-items: center;
  background: #eaf3bd;
  color: #526738;
}

.admin-link-card strong {
  align-self: end;
  font-size: 10px;
}

.admin-link-card small {
  color: #829187;
  font-size: 8px;
}

.admin-link-card .link-arrow {
  position: absolute;
  top: 15px;
  right: 15px;
  color: #87998d;
}

.admin-note {
  color: #929f95;
  font-size: 9px;
  line-height: 1.6;
}

@media (max-width: 960px) {
  .admin-stats {
    grid-template-columns: repeat(3, 1fr);
  }

  .admin-columns {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 560px) {
  .approval-item {
    align-items: flex-start;
    flex-direction: column;
  }

  .approval-actions {
    flex-wrap: wrap;
  }

  .registration-tabs {
    overflow-x: auto;
  }

  .registration-tabs button {
    flex: 0 0 auto;
  }

  .detail-grid {
    grid-template-columns: 1fr;
  }

  .verification-table {
    display: none;
  }

  .verification-cards {
    display: grid;
  }

  .admin-stats {
    grid-template-columns: repeat(2, 1fr);
  }

  .admin-links {
    grid-template-columns: 1fr;
  }
}
</style>
