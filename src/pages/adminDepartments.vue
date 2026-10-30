<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import NorthstarBackButton from '@/components/NorthstarBackButton.vue'
import { useAuthStore } from '@/stores/auth'
import { departmentRankLabel, isDepartmentCandidateEligible, isDepartmentRankAssignable, validateHeadReplacement } from '@/utils/departmentHierarchy'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

type Assignment = {
  department_id: string | null
  department_name: string | null
  user_id: string | null
  display_name: string | null
  role: string | null
  department_level: number | null
  approval_status: string | null
  employment_status: string | null
  registration_completed: boolean | null
  email_verified: boolean | null
}
type Department = { id: string, name: string }

const auth = useAuthStore()
const assignments = ref<Assignment[]>([])
const departments = ref<Department[]>([])
const loading = ref(false)
const savingId = ref('')
const error = ref('')
const success = ref('')
const drafts = ref<Record<string, { departmentId: string, level: string }>>({})
const headDrafts = ref<Record<string, { userId: string, outgoingLevel: string }>>({})
const pendingHeadChange = ref<{ department: Department, currentHead: Assignment | null, proposedHead: Assignment, outgoingLevel: string } | null>(null)
const eligible = computed(() => assignments.value.filter(row => row.user_id && isDepartmentRankAssignable(row)))
const rankLabel = departmentRankLabel
const departmentHead = (departmentId: string) => eligible.value.find(row => row.department_id === departmentId && row.department_level === 1) ?? null
const departmentCandidates = (departmentId: string) => eligible.value.filter(row => row.department_id === departmentId && isDepartmentCandidateEligible(row))

async function load () {
  if (!auth.isAdmin || !supabase || !isSupabaseConfigured) {
    error.value = 'Only the designated administrator can manage department assignments.'
    return
  }
  loading.value = true
  error.value = ''
  const assignmentResult = await supabase.rpc('northstar_admin_list_department_management')
  loading.value = false
  if (assignmentResult.error) {
    error.value = `Could not load department assignments: ${assignmentResult.error.message}`
    return
  }
  assignments.value = assignmentResult.data ?? []
  departments.value = [...new Map(assignments.value
    .filter(row => row.department_id && row.department_name)
    .map(row => [row.department_id!, { id: row.department_id!, name: row.department_name! }])).values()]
  drafts.value = Object.fromEntries(eligible.value.map(row => [row.user_id!, {
    departmentId: row.department_id ?? '',
    level: row.department_level ? String(row.department_level) : '',
  }]))
  headDrafts.value = Object.fromEntries(departments.value.map(department => [department.id, {
    userId: '',
    outgoingLevel: '',
  }]))
}

async function save (row: Assignment) {
  if (!auth.isAdmin || !row.user_id || !supabase || savingId.value) return
  const draft = drafts.value[row.user_id]
  const departmentId = draft?.departmentId || null
  const level = draft?.level ? Number(draft.level) : null
  if ((departmentId === null) !== (level === null) || (level !== null && (!Number.isInteger(level) || level < 1 || level > 5))) {
    error.value = 'Choose both a department and a level, or clear both to unassign this employee.'
    return
  }
  if (level === 1) {
    const department = departments.value.find(item => item.id === departmentId)
    const proposedHead = eligible.value.find(item => item.user_id === row.user_id && item.department_id === departmentId)
    if (!department || !proposedHead) {
      error.value = 'A department head must be an eligible employee or manager already assigned to the selected department.'
      return
    }
    requestHeadChange(department, proposedHead)
    return
  }
  savingId.value = row.user_id
  error.value = ''
  success.value = ''
  const { error: rpcError } = await supabase.rpc('northstar_admin_assign_department_level', {
    p_user_id: row.user_id,
    p_department_id: departmentId,
    p_department_level: level,
  })
  savingId.value = ''
  if (rpcError) {
    error.value = `Could not save assignment: ${rpcError.message}`
    return
  }
  success.value = 'Department assignment saved.'
  await load()
}

function requestHeadChange (department: Department, proposedHead: Assignment) {
  const currentHead = departmentHead(department.id)
  if (currentHead?.user_id === proposedHead.user_id) {
    success.value = `${proposedHead.display_name || 'Employee'} is already the head of ${department.name}.`
    return
  }
  pendingHeadChange.value = {
    department,
    currentHead,
    proposedHead,
    outgoingLevel: currentHead ? (headDrafts.value[department.id]?.outgoingLevel || '') : '',
  }
  error.value = ''
  success.value = ''
}

async function confirmHeadChange () {
  const change = pendingHeadChange.value
  if (!auth.isAdmin || !change || !supabase || savingId.value) return
  const outgoingLevel = change.currentHead ? Number(change.outgoingLevel) : null
  const validationMessage = validateHeadReplacement(change.currentHead?.user_id ?? null, change.proposedHead.user_id, outgoingLevel)
  if (validationMessage) {
    error.value = validationMessage
    return
  }
  savingId.value = change.proposedHead.user_id ?? 'department-head'
  error.value = ''
  success.value = ''
  const { error: rpcError } = await supabase.rpc('northstar_admin_set_department_head', {
    p_department_id: change.department.id,
    p_user_id: change.proposedHead.user_id,
    p_outgoing_department_level: outgoingLevel,
  })
  savingId.value = ''
  if (rpcError) {
    error.value = `Could not update the department head: ${rpcError.message}`
    return
  }
  success.value = `${change.proposedHead.display_name || 'Employee'} is now the head of ${change.department.name}.`
  pendingHeadChange.value = null
  await load()
}

onMounted(() => { void load() })
</script>

<template>
  <main class="department-admin">
    <header class="page-heading"><div class="heading-main"><NorthstarBackButton /><div><p class="eyebrow">ADMINISTRATION</p><h1>Department hierarchy</h1><p>Assign approved employees to department levels. Only Level 1 has department-head permissions.</p></div></div><button class="secondary-action" type="button" :disabled="loading" @click="load">{{ loading ? 'Loading…' : 'Refresh' }}</button></header>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    <p v-if="success" class="form-success" role="status">{{ success }}</p>
    <section class="surface-card assignment-panel">
      <p v-if="loading" role="status">Loading approved employees and departments…</p>
      <p v-else-if="eligible.length === 0">No approved active employees are available for assignment.</p>
      <section v-if="!loading && departments.length" class="department-head-list" aria-labelledby="department-heads-title">
        <h2 id="department-heads-title">Department heads</h2>
        <article v-for="department in departments" :key="department.id" class="department-head-card">
          <div class="head-summary">
            <strong>{{ department.name }}</strong>
            <template v-if="departmentHead(department.id)">
              <span>{{ departmentHead(department.id)?.display_name || 'Name unavailable' }}</span>
              <small>{{ rankLabel(departmentHead(department.id)?.department_level ?? null) }} · {{ departmentHead(department.id)?.approval_status }} · {{ departmentHead(department.id)?.employment_status }}</small>
            </template>
            <span v-else class="no-head">No department head assigned</span>
          </div>
          <label><span>Eligible appointee</span>
            <select v-model="headDrafts[department.id].userId" :aria-label="`Choose department head for ${department.name}`">
              <option value="">Choose an eligible employee</option>
              <option v-for="candidate in departmentCandidates(department.id)" :key="candidate.user_id!" :value="candidate.user_id!">
                {{ candidate.display_name || 'Name unavailable' }} · {{ candidate.role }}
              </option>
            </select>
          </label>
          <label v-if="departmentHead(department.id)"><span>Rank for outgoing head</span>
            <select v-model="headDrafts[department.id].outgoingLevel" :aria-label="`Rank for current head leaving ${department.name}`">
              <option value="">Choose a new rank</option>
              <option v-for="level in [2, 3, 4, 5]" :key="level" :value="String(level)">{{ rankLabel(level) }}</option>
            </select>
          </label>
          <button class="primary-action" type="button" :disabled="!headDrafts[department.id]?.userId || Boolean(savingId)" @click="requestHeadChange(department, eligible.find(row => row.user_id === headDrafts[department.id]?.userId)!)">
            {{ departmentHead(department.id) ? 'Replace head' : 'Assign head' }}
          </button>
        </article>
      </section>
      <div v-if="eligible.length" class="assignment-list">
        <article v-for="employee in eligible" :key="employee.user_id!" class="assignment-row">
          <div><strong>{{ employee.display_name || 'Name unavailable' }}</strong><small>{{ employee.role }} · {{ employee.department_name || 'No department' }} · {{ rankLabel(employee.department_level) }}</small></div>
          <label><span>Department</span><select v-model="drafts[employee.user_id!].departmentId"><option value="">Unassigned</option><option v-for="department in departments" :key="department.id" :value="department.id">{{ department.name }}</option></select></label>
          <label><span>Department Rank</span><select v-model="drafts[employee.user_id!].level"><option value="">Unassigned</option><option v-for="level in [1, 2, 3, 4, 5]" :key="level" :value="String(level)">{{ rankLabel(level) }}</option></select></label>
          <button class="primary-action" type="button" :disabled="savingId === employee.user_id" @click="save(employee)">{{ savingId === employee.user_id ? 'Saving…' : 'Save' }}</button>
        </article>
      </div>
      <p class="permission-note">The database verifies administrator authority, employee eligibility, level range, and the one-active-head-per-department rule.</p>
    </section>
    <v-dialog :model-value="Boolean(pendingHeadChange)" max-width="540" @update:model-value="!$event && (pendingHeadChange = null)">
      <v-card v-if="pendingHeadChange" class="confirm-card">
        <v-card-title>Confirm department head assignment</v-card-title>
        <v-card-text>
          <p><strong>Department:</strong> {{ pendingHeadChange.department.name }}</p>
          <p><strong>Current head:</strong> {{ pendingHeadChange.currentHead?.display_name || 'No head assigned' }}</p>
          <p><strong>Proposed replacement:</strong> {{ pendingHeadChange.proposedHead.display_name || 'Name unavailable' }}</p>
          <label v-if="pendingHeadChange.currentHead"><span>New rank for the outgoing head</span>
            <select v-model="pendingHeadChange.outgoingLevel" aria-label="New rank for outgoing department head">
              <option value="">Choose a rank</option>
              <option v-for="level in [2, 3, 4, 5]" :key="level" :value="String(level)">{{ rankLabel(level) }}</option>
            </select>
          </label>
        </v-card-text>
        <v-card-actions><v-spacer /><v-btn variant="text" @click="pendingHeadChange = null">Cancel</v-btn><v-btn color="primary" :disabled="Boolean(savingId) || Boolean(pendingHeadChange.currentHead && !pendingHeadChange.outgoingLevel)" @click="confirmHeadChange">{{ savingId ? 'Saving…' : 'Confirm assignment' }}</v-btn></v-card-actions>
      </v-card>
    </v-dialog>
  </main>
</template>

<style scoped>
.department-admin { color: var(--ns-text-18352d, #18352d); }
.page-heading, .heading-main { display: flex; align-items: center; gap: 14px; }
.page-heading { justify-content: space-between; margin-bottom: 18px; }
.page-heading h1 { margin: 4px 0; font-size: 25px; }
.page-heading p, .assignment-row small, .permission-note { color: var(--ns-text-718178, #718178); }
.eyebrow { font: 10px "DM Mono", monospace; letter-spacing: 1px; }
.assignment-panel { padding: 18px; }
.department-head-list { display: grid; gap: 10px; margin-bottom: 24px; }.department-head-list h2 { margin: 0 0 4px; font-size: 16px; }.department-head-card { display: grid; grid-template-columns: minmax(180px,1fr) minmax(190px,1fr) minmax(190px,1fr) auto; align-items: end; gap: 12px; border: 1px solid var(--ns-border-dce4d8,#dce4d8); border-radius: 8px; padding: 14px; }.head-summary { display: grid; gap: 5px; }.head-summary small,.no-head { color: var(--ns-text-718178,#718178); font-size: 10px; }.department-head-card label,.confirm-card label { display: grid; gap: 5px; color: var(--ns-text-718178,#718178); font-size: 10px; }.department-head-card select,.confirm-card select { min-height: 38px; border: 1px solid var(--ns-border-dce4d8,#dce4d8); border-radius: 5px; padding: 7px; background: white; color: var(--ns-text-18352d,#18352d); }
.assignment-list { display: grid; }
.assignment-row { display: grid; grid-template-columns: minmax(180px, 1fr) minmax(160px, .8fr) 150px auto; align-items: end; gap: 12px; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding: 13px 0; }
.assignment-row > div { display: grid; gap: 5px; }
.assignment-row small { font-size: 10px; }
.assignment-row label { display: grid; gap: 5px; color: var(--ns-text-718178, #718178); font-size: 10px; }
.assignment-row select { min-height: 38px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); border-radius: 5px; padding: 7px; background: white; color: var(--ns-text-18352d, #18352d); }
.permission-note { margin: 15px 0 0; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding-top: 12px; font-size: 10px; }
.form-error { color: #a34c39; }
.form-success { color: #23724a; }
@media (max-width: 760px) { .assignment-row,.department-head-card { grid-template-columns: 1fr 1fr; } .assignment-row > div,.head-summary { grid-column: 1 / -1; } }
</style>
