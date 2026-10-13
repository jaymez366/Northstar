<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useWorkspaceStore } from '@/stores/workspace'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

const workspace = useWorkspaceStore()
const employeeSearch = ref('')
const pendingEmployees = ref<{
  user_id: string
  first_name: string
  last_name: string
  work_email: string
  department: string
  job_title: string
  employee_id: string | null
  employment_type: string
  office_location: string
  manager_name: string | null
  bio: string | null
}[]>([])
const emailVerificationRecords = ref<{
  user_id: string
  first_name: string
  last_name: string
  email: string
  email_verification_status: 'Verified' | 'Not Verified'
  email_verified_at: string | null
  account_created_at: string
}[]>([])
const approvalsLoading = ref(false)
const approvalError = ref('')
const updatingEmployeeId = ref('')
const verificationRecordsLoading = ref(false)
const verificationRecordsError = ref('')
const filteredEmployees = computed(() => workspace.employees.filter(employee => `${employee.firstName} ${employee.lastName} ${employee.department}`.toLowerCase().includes(employeeSearch.value.trim().toLowerCase())))
const displayedActivities = computed(() => workspace.activityLogs.map(item => ({
    id: item.id,
    icon: item.action.includes('announcement') ? 'mdi-bullhorn-outline' : (item.action.includes('event') ? 'mdi-calendar-outline' : 'mdi-file-document-outline'),
    title: item.description,
    actor: item.user,
    time: new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.createdAt)),
  })))

  async function loadPendingEmployees () {
    if (!isSupabaseConfigured || !supabase) {
      approvalError.value = 'Employee approvals require a configured Northstar Supabase connection.'
      return
    }
    approvalsLoading.value = true
    approvalError.value = ''
    const { data, error } = await supabase.rpc('admin_list_pending_employees')
    approvalsLoading.value = false
    if (error) {
      approvalError.value = `Could not load employee registrations: ${error.message}`
      console.error(approvalError.value, error)
      return
    }
    pendingEmployees.value = data ?? []
  }

  async function loadEmailVerificationRecords () {
    if (!isSupabaseConfigured || !supabase) {
      verificationRecordsError.value = 'Email verification records require a configured Northstar Supabase connection.'
      return
    }
    verificationRecordsLoading.value = true
    verificationRecordsError.value = ''
    const { data, error } = await supabase.rpc('admin_list_email_verification_status')
    verificationRecordsLoading.value = false
    if (error) {
      verificationRecordsError.value = `Could not load email verification records: ${error.message}`
      console.error(verificationRecordsError.value, error)
      return
    }
    emailVerificationRecords.value = data ?? []
  }

  function formatRecordDate (value: string | null) {
    if (!value) return '—'
    return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  }

  async function setEmployeeApproval (userId: string, approvalStatus: 'approved' | 'rejected') {
    if (!supabase || updatingEmployeeId.value) return
    updatingEmployeeId.value = userId
    approvalError.value = ''
    const { error } = await supabase.rpc('admin_set_employee_approval', {
      p_user_id: userId,
      p_approval_status: approvalStatus,
    })
    updatingEmployeeId.value = ''
    if (error) {
      approvalError.value = `Could not update employee approval: ${error.message}`
      console.error(approvalError.value, error)
      return
    }
    await loadPendingEmployees()
    await workspace.load()
  }

  onMounted(() => {
    void loadPendingEmployees()
    void loadEmailVerificationRecords()
  })
</script>

<template>
  <main>
    <header class="page-heading">
      <div>
        <p class="eyebrow">ADMINISTRATION</p>
        <h1>Admin dashboard</h1>
        <p>Organization activity and management shortcuts in one place.</p>
      </div><span class="admin-badge"><v-icon icon="mdi-shield-check-outline" size="16" /> ADMIN WORKSPACE</span>
    </header>

    <section aria-label="Organization metrics" class="admin-stats">
      <article class="surface-card"><span><v-icon icon="mdi-account-group-outline" /></span><small>TOTAL
          EMPLOYEES</small><strong>{{ workspace.employees.length }}</strong><router-link to="/employees">View directory
          <v-icon icon="mdi-arrow-right" size="13" /></router-link></article>
      <article class="surface-card"><span><v-icon icon="mdi-domain" /></span><small>DEPARTMENTS</small><strong>{{
        workspace.departments.length }}</strong><router-link to="/departments">View departments <v-icon
            icon="mdi-arrow-right" size="13" /></router-link></article>
      <article class="surface-card"><span><v-icon
            icon="mdi-bullhorn-outline" /></span><small>ANNOUNCEMENTS</small><strong>{{ workspace.announcements.length
          }}</strong><router-link to="/announcements">Manage updates <v-icon icon="mdi-arrow-right"
            size="13" /></router-link></article>
      <article class="surface-card"><span><v-icon icon="mdi-calendar-outline" /></span><small>UPCOMING
          EVENTS</small><strong>{{ workspace.events.length }}</strong><router-link to="/events">Manage events <v-icon
            icon="mdi-arrow-right" size="13" /></router-link></article>
      <article class="surface-card"><span><v-icon
            icon="mdi-message-outline" /></span><small>CONVERSATIONS</small><strong>{{ workspace.conversations.length
          }}</strong><router-link to="/messages">View messages <v-icon icon="mdi-arrow-right" size="13" /></router-link>
      </article>
    </section>

    <section class="approval-panel surface-card">
      <div class="panel-heading">
        <div>
          <p class="eyebrow">EMPLOYEE ONBOARDING</p>
          <h2>Registrations awaiting approval</h2>
        </div>
        <button class="secondary-action" :disabled="approvalsLoading" type="button" @click="loadPendingEmployees">
          Refresh
        </button>
      </div>

      <p v-if="approvalError" class="approval-error" role="alert">{{ approvalError }}</p>
      <p v-else-if="approvalsLoading" class="approval-empty">Loading employee registrations…</p>
      <p v-else-if="pendingEmployees.length === 0" class="approval-empty">No employee registrations are awaiting approval.</p>

      <div v-else class="approval-list">
        <article v-for="employee in pendingEmployees" :key="employee.user_id" class="approval-item">
          <div class="approval-details">
            <strong>{{ employee.first_name }} {{ employee.last_name }}</strong>
            <span>{{ employee.work_email }} · {{ employee.department }} · {{ employee.job_title }}</span>
            <small>
              {{ employee.employment_type }} · {{ employee.office_location }}
              <template v-if="employee.employee_id"> · ID {{ employee.employee_id }}</template>
              <template v-if="employee.manager_name"> · Manager {{ employee.manager_name }}</template>
            </small>
            <small v-if="employee.bio">{{ employee.bio }}</small>
          </div>
          <div class="approval-actions">
            <button
              class="approve-button"
              :disabled="updatingEmployeeId === employee.user_id"
              type="button"
              @click="setEmployeeApproval(employee.user_id, 'approved')"
            >Approve</button>
            <button
              class="reject-button"
              :disabled="updatingEmployeeId === employee.user_id"
              type="button"
              @click="setEmployeeApproval(employee.user_id, 'rejected')"
            >Reject</button>
          </div>
        </article>
      </div>
    </section>

    <section class="approval-panel surface-card">
      <div class="panel-heading">
        <div>
          <p class="eyebrow">SUPABASE AUTHENTICATION</p>
          <h2>Email verification status</h2>
        </div>
        <button class="secondary-action" :disabled="verificationRecordsLoading" type="button" @click="loadEmailVerificationRecords">
          {{ verificationRecordsLoading ? 'Refreshing…' : 'Refresh' }}
        </button>
      </div>

      <p v-if="verificationRecordsError" class="approval-error" role="alert">{{ verificationRecordsError }}</p>
      <p v-else-if="verificationRecordsLoading" class="approval-empty">Loading email verification records…</p>
      <p v-else-if="emailVerificationRecords.length === 0" class="approval-empty">No user accounts were found.</p>

      <div v-else class="table-scroll">
        <table class="data-table">
          <thead>
            <tr>
              <th>USER ID</th>
              <th>NAME</th>
              <th>EMAIL</th>
              <th>EMAIL STATUS</th>
              <th>VERIFIED AT</th>
              <th>ACCOUNT CREATED</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="record in emailVerificationRecords" :key="record.user_id">
              <td>{{ record.user_id }}</td>
              <td>{{ `${record.first_name} ${record.last_name}`.trim() || '—' }}</td>
              <td>{{ record.email }}</td>
              <td>
                <span class="verification-status" :class="{ verified: record.email_verification_status === 'Verified' }">
                  {{ record.email_verification_status }}
                </span>
              </td>
              <td>{{ formatRecordDate(record.email_verified_at) }}</td>
              <td>{{ formatRecordDate(record.account_created_at) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <div class="admin-columns">
      <section class="management-panel surface-card">
        <div class="panel-heading">
          <div>
            <p class="eyebrow">PEOPLE</p>
            <h2>Employee management</h2>
          </div><router-link to="/employees">Full directory <v-icon icon="mdi-arrow-right" size="14" /></router-link>
        </div>
        <input v-model="employeeSearch" aria-label="Search employee records" class="field-control"
          placeholder="Search employees">
        <div class="table-scroll">
          <table class="data-table">
            <thead>
              <tr>
                <th>EMPLOYEE</th>
                <th>DEPARTMENT</th>
                <th>STATUS</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="employee in filteredEmployees.slice(0, 6)" :key="employee.id">
                <td><span class="table-employee"><i :style="{ background: employee.color }">{{ employee.initials
                      }}</i><span><strong>{{ employee.firstName }} {{ employee.lastName }}</strong><small>{{
                        employee.title }}</small></span></span></td>
                <td>{{ employee.department }}</td>
                <td><span class="table-status" :class="{ online: employee.online }">{{ employee.online ? 'Online' :
                    'Offline' }}</span></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="management-panel surface-card">
        <div class="panel-heading">
          <div>
            <p class="eyebrow">RECENT ACTIVITY</p>
            <h2>What’s happening</h2>
          </div>
        </div>
        <div class="activity-list">
          <article v-for="activity in displayedActivities" :key="activity.id"><span><v-icon :icon="activity.icon"
                size="18" /></span>
            <div><strong>{{ activity.title }}</strong><small>{{ activity.actor }} · {{ activity.time }}</small></div>
          </article>
          <p v-if="displayedActivities.length === 0" class="no-activity">No recent activity has been recorded.</p>
        </div>
      </section>
    </div>

    <section class="admin-links">
      <router-link class="surface-card admin-link-card" to="/announcements"><span><v-icon
            icon="mdi-bullhorn-outline" /></span><strong>Announcement management</strong><small>Review and publish
          company-wide updates</small><v-icon class="link-arrow" icon="mdi-arrow-top-right" size="18" /></router-link>
      <router-link class="surface-card admin-link-card" to="/departments"><span><v-icon
            icon="mdi-domain" /></span><strong>Department management</strong><small>Review teams and their
          members</small><v-icon class="link-arrow" icon="mdi-arrow-top-right" size="18" /></router-link>
    </section>

    <p v-if="!isSupabaseConfigured" class="admin-note">Configure the Northstar Supabase project to load organization data.</p>
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
.approval-panel { margin: 14px 0; padding: 18px; }
.approval-panel .panel-heading { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.approval-panel h2 { margin: 4px 0 0; color: #18352d; font-size: 14px; }
.approval-empty, .approval-error { color: #829187; font-size: 10px; }
.approval-error { color: #a34c39; }
.approval-list { display: grid; gap: 9px; margin-top: 14px; }
.approval-item { display: flex; align-items: center; justify-content: space-between; gap: 16px; border-top: 1px solid #edf0e9; padding-top: 12px; }
.approval-details { display: grid; min-width: 0; gap: 5px; }
.approval-details strong { color: #18352d; font-size: 11px; }
.approval-details span, .approval-details small { color: #718178; font-size: 9px; line-height: 1.5; }
.approval-actions { display: flex; flex: 0 0 auto; gap: 6px; }
.approval-actions button { border: 0; padding: 8px 10px; cursor: pointer; font: 700 9px "Manrope", sans-serif; }
.approve-button { background: #18352d; color: #f5f6ee; }
.reject-button { background: #fae6de; color: #a44c38; }
.approval-actions button:disabled { cursor: wait; opacity: .6; }
.verification-status { color: #a34c39; font-weight: 700; }
.verification-status.verified { color: #4b8058; }

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
  .approval-item { align-items: flex-start; flex-direction: column; }
  .admin-stats {
    grid-template-columns: repeat(2, 1fr);
  }

  .admin-links {
    grid-template-columns: 1fr;
  }
}
</style>
