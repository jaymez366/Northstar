<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import NorthstarBackButton from '@/components/NorthstarBackButton.vue'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

type IncidentStatus = 'open' | 'investigating' | 'resolved' | 'closed'
type IncidentSeverity = 'low' | 'medium' | 'high' | 'critical'
type IncidentVisibility = 'reporter' | 'response_team' | 'admin'
type Incident = {
  id: string
  title: string
  description: string
  category: string
  severity: IncidentSeverity
  location: string
  reported_by: string
  reported_at: string
  status: IncidentStatus
  assigned_responder: string | null
  resolution_details: string | null
  created_at: string
  updated_at: string
}
type IncidentUpdate = {
  id: string
  incident_id: string
  actor_id: string | null
  event_type: string
  visibility: IncidentVisibility
  old_status: IncidentStatus | null
  new_status: IncidentStatus | null
  old_severity: IncidentSeverity | null
  new_severity: IncidentSeverity | null
  old_assigned_responder: string | null
  new_assigned_responder: string | null
  old_resolution_details: string | null
  new_resolution_details: string | null
  details: string | null
  created_at: string
}
type Responder = { user_id: string, first_name: string, last_name: string }

const administratorEmail = 'northstaradmin34@gmail.com'
const auth = useAuthStore()
const route = useRoute()
const incidents = ref<Incident[]>([])
const updates = ref<IncidentUpdate[]>([])
const responders = ref<Responder[]>([])
const loading = ref(false)
const submitting = ref(false)
const savingIncidentId = ref('')
const loadError = ref('')
const formError = ref('')
const actionError = ref('')
const successMessage = ref('')
const search = ref('')
const expandedIncidentId = ref('')
const reportForm = ref({ title: '', description: '', category: '', severity: '', location: '' })
const reportCategories = [
  { value: 'fire', label: 'Fire' },
  { value: 'medical', label: 'Medical emergency' },
  { value: 'security', label: 'Security' },
  { value: 'natural_disaster', label: 'Natural disaster' },
  { value: 'hazardous_material', label: 'Hazardous material' },
  { value: 'infrastructure', label: 'Infrastructure' },
  { value: 'other', label: 'Other' },
]
const severityOptions: IncidentSeverity[] = ['low', 'medium', 'high', 'critical']
const statusOptions: IncidentStatus[] = ['open', 'investigating', 'resolved', 'closed']
const isDesignatedAdmin = computed(() => auth.isAdmin && auth.emailVerified
  && auth.userEmail.trim().toLowerCase() === administratorEmail)
const canReportIncident = computed(() => !isDesignatedAdmin.value && auth.canAccessEmployeeWorkspace)
const filteredIncidents = computed(() => {
  const query = search.value.trim().toLowerCase()
  if (!query) return incidents.value
  return incidents.value.filter(incident =>
    [incident.title, incident.description, incident.category, incident.location, incident.severity, incident.status]
      .some(value => value.toLowerCase().includes(query)))
})
const overviewItems = computed(() => [
  { label: 'Total incidents', icon: 'mdi-alert-circle-outline', tone: 'green', value: loading.value ? '…' : loadError.value ? '—' : incidents.value.length },
  { label: 'Active incidents', icon: 'mdi-radio-tower', tone: 'amber', value: loading.value ? '…' : loadError.value ? '—' : incidents.value.filter(item => ['open', 'investigating'].includes(item.status)).length },
  { label: 'Resolved incidents', icon: 'mdi-check-circle-outline', tone: 'blue', value: loading.value ? '…' : loadError.value ? '—' : incidents.value.filter(item => ['resolved', 'closed'].includes(item.status)).length },
  { label: 'Critical incidents', icon: 'mdi-alert-octagon-outline', tone: 'red', value: loading.value ? '…' : loadError.value ? '—' : incidents.value.filter(item => item.severity === 'critical').length },
])
const resourceItems = [
  { title: 'Response plans', description: 'Approved disaster response plans will appear here.', icon: 'mdi-clipboard-text-outline' },
  { title: 'Emergency contacts', description: 'Verified organization contacts are not configured.', icon: 'mdi-card-account-phone-outline' },
  { title: 'Safety guidance', description: 'Approved safety guidance is not available in this workspace.', icon: 'mdi-shield-check-outline' },
]
let incidentChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null

function formatDate(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

function employeeLabel(id: string | null) {
  if (!id) return 'Unassigned'
  if (id === auth.userId) return 'You'
  const responder = responders.value.find(item => item.user_id === id)
  return responder ? `${responder.first_name} ${responder.last_name}`.trim() : 'Assigned employee'
}

function historyFor(incidentId: string) {
  return updates.value.filter(update => update.incident_id === incidentId)
}

async function loadIncidents() {
  if (!isSupabaseConfigured || !supabase) {
    loadError.value = 'Incident records require a configured Northstar Supabase connection.'
    return
  }
  loading.value = true
  loadError.value = ''
  try {
    const [incidentResult, updateResult] = await Promise.all([
      supabase.from('northstar_incidents')
        .select('id,title,description,category,severity,location,reported_by,reported_at,status,assigned_responder,resolution_details,created_at,updated_at')
        .order('reported_at', { ascending: false }),
      supabase.from('northstar_incident_updates')
        .select('id,incident_id,actor_id,event_type,visibility,old_status,new_status,old_severity,new_severity,old_assigned_responder,new_assigned_responder,old_resolution_details,new_resolution_details,details,created_at')
        .order('created_at', { ascending: false }),
    ])
    if (incidentResult.error) throw new Error(`Could not load incident reports: ${incidentResult.error.message}`)
    if (updateResult.error) throw new Error(`Could not load incident history: ${updateResult.error.message}`)
    incidents.value = (incidentResult.data ?? []) as Incident[]
    updates.value = (updateResult.data ?? []) as IncidentUpdate[]
    const linkedIncidentId = typeof route.query.incident === 'string' ? route.query.incident : ''
    if (incidents.value.some(incident => incident.id === linkedIncidentId)) {
      expandedIncidentId.value = linkedIncidentId
    }
  } catch (error) {
    loadError.value = error instanceof Error ? error.message : 'Could not load incidents. Please try again.'
    incidents.value = []
    updates.value = []
    console.error('Northstar incident load failed', error)
  } finally {
    loading.value = false
  }
}

async function loadResponders() {
  if (!isDesignatedAdmin.value || !supabase) return
  const { data, error } = await supabase.rpc('northstar_admin_list_employee_registrations')
  if (error) {
    actionError.value = `Could not load responder list: ${error.message}`
    console.error('Northstar responder list failed', error)
    return
  }
  responders.value = (data ?? [])
    .filter((item: { approval_status: string | null, employment_status: string | null, email_verification_status: string }) =>
      item.approval_status === 'approved' && item.employment_status === 'active' && item.email_verification_status === 'Verified')
    .map((item: { user_id: string, first_name: string, last_name: string }) => ({
      user_id: item.user_id,
      first_name: item.first_name,
      last_name: item.last_name,
    }))
}

async function submitIncident() {
  if (!canReportIncident.value || !supabase || submitting.value) return
  const values = {
    title: reportForm.value.title.trim(),
    description: reportForm.value.description.trim(),
    category: reportForm.value.category,
    severity: reportForm.value.severity,
    location: reportForm.value.location.trim(),
  }
  if (values.title.length < 5 || values.description.length < 10 || values.location.length < 2
      || !values.category || !values.severity) {
    formError.value = 'Complete each field. Title needs 5 characters, description 10, and location 2.'
    return
  }
  submitting.value = true
  formError.value = ''
  actionError.value = ''
  successMessage.value = ''
  try {
    const { data, error } = await supabase.rpc('northstar_report_incident', {
      p_title: values.title,
      p_description: values.description,
      p_category: values.category,
      p_severity: values.severity,
      p_location: values.location,
    })
    if (error) throw error
    if (typeof data !== 'string') throw new Error('Supabase did not return the new incident ID.')
    reportForm.value = { title: '', description: '', category: '', severity: '', location: '' }
    successMessage.value = 'Your incident report was submitted.'
    await loadIncidents()
  } catch (error) {
    formError.value = error instanceof Error ? error.message : 'Could not submit the incident report. Please try again.'
    console.error('Northstar incident report failed', error)
  } finally {
    submitting.value = false
  }
}

function newAdminDraft(incident: Incident) {
  return {
    status: incident.status,
    severity: incident.severity,
    assignedResponder: incident.assigned_responder ?? '',
    resolutionDetails: incident.resolution_details ?? '',
    update: '',
    visibility: 'reporter' as IncidentVisibility,
  }
}

const adminDrafts = ref<Record<string, ReturnType<typeof newAdminDraft>>>({})

function draftFor(incident: Incident) {
  return adminDrafts.value[incident.id] ?? (adminDrafts.value[incident.id] = newAdminDraft(incident))
}

async function saveIncidentUpdate(incident: Incident) {
  if (!isDesignatedAdmin.value || !supabase || savingIncidentId.value) return
  const draft = draftFor(incident)
  const update = draft.update.trim()
  if (!update) {
    actionError.value = 'Enter an update before saving.'
    return
  }
  savingIncidentId.value = incident.id
  actionError.value = ''
  successMessage.value = ''
  try {
    const isPrivateNote = draft.visibility === 'admin'
    const { error } = await supabase.rpc('northstar_admin_update_incident', {
      p_incident_id: incident.id,
      p_status: isPrivateNote ? incident.status : draft.status,
      p_severity: isPrivateNote ? incident.severity : draft.severity,
      p_assigned_responder: isPrivateNote ? incident.assigned_responder : (draft.assignedResponder || null),
      p_resolution_details: isPrivateNote ? incident.resolution_details : (draft.resolutionDetails.trim() || null),
      p_update: update,
      p_visibility: draft.visibility,
    })
    if (error) throw error
    successMessage.value = isPrivateNote ? 'Private administrator note saved.' : 'Incident update saved.'
    delete adminDrafts.value[incident.id]
    await loadIncidents()
  } catch (error) {
    actionError.value = error instanceof Error ? error.message : 'Could not save the incident update. Please try again.'
    console.error('Northstar incident update failed', error)
  } finally {
    savingIncidentId.value = ''
  }
}

function subscribeToIncidents() {
  if (!supabase || incidentChannel) return
  incidentChannel = supabase.channel('northstar-disaster-management')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'northstar_incidents' }, () => void loadIncidents())
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'northstar_incident_updates' }, () => void loadIncidents())
    .subscribe()
}

onMounted(() => {
  void loadIncidents()
  if (isDesignatedAdmin.value) void loadResponders()
  subscribeToIncidents()
})

onUnmounted(() => {
  if (incidentChannel && supabase) void supabase.removeChannel(incidentChannel)
  incidentChannel = null
})
</script>

<template>
  <main class="disaster-dashboard">
    <header class="dashboard-header">
      <div class="heading-copy">
        <NorthstarBackButton />
        <span class="heading-icon"><v-icon icon="mdi-shield-alert-outline" size="23" /></span>
        <div>
          <p class="eyebrow">BUSINESS CONTINUITY</p>
          <h1>Disaster Management</h1>
          <p class="intro">A central view for incident awareness, response coordination, and preparedness resources.</p>
        </div>
      </div>
      <div class="connection-state" :class="{ connected: !loadError && !loading, failed: Boolean(loadError) }">
        <span /> {{ loading ? 'Loading incident data' : loadError ? 'Incident data unavailable' : 'Live incident data' }}
      </div>
    </header>

    <section aria-label="Incident overview" class="overview-grid">
      <article v-for="item in overviewItems" :key="item.label" class="overview-card surface-card">
        <div class="overview-top">
          <span class="overview-icon" :class="item.tone"><v-icon :icon="item.icon" size="19" /></span>
        <span class="unavailable-tag">{{ loading ? 'Loading' : loadError ? 'Unavailable' : 'Live data' }}</span>
        </div>
        <p>{{ item.label }}</p>
        <strong>{{ item.value }}</strong>
        <small>{{ loadError ? 'Incident records could not be loaded.' : 'Based on incidents visible to your account.' }}</small>
      </article>
    </section>

    <section class="section-card surface-card" aria-labelledby="active-incidents-heading">
      <div class="section-heading">
        <div>
          <p class="eyebrow">LIVE RESPONSE</p>
          <h2 id="active-incidents-heading">Active emergencies</h2>
          <p class="section-description">Current incidents and their response status.</p>
        </div>
        <span class="section-count">{{ loading ? 'Loading' : `${incidents.filter(item => ['open', 'investigating'].includes(item.status)).length} active` }}</span>
      </div>
      <div v-if="loadError" class="empty-panel error-panel" role="alert">
        <span class="empty-icon"><v-icon icon="mdi-alert-circle-outline" size="22" /></span>
        <div><strong>Incident data could not be loaded</strong><p>{{ loadError }}</p><button class="inline-action" type="button" @click="loadIncidents">Try again</button></div>
      </div>
      <div v-else-if="loading" class="empty-panel" aria-live="polite">
        <v-progress-circular aria-label="Loading incidents" indeterminate size="22" width="2" />
        <div><strong>Loading incident records</strong><p>Checking the incidents available to your account.</p></div>
      </div>
      <div v-else-if="incidents.filter(item => ['open', 'investigating'].includes(item.status)).length === 0" class="empty-panel">
        <span class="empty-icon"><v-icon icon="mdi-broadcast-off" size="22" /></span>
        <div>
          <strong>No active emergencies</strong>
          <p>There are no active incidents visible to your account.</p>
        </div>
      </div>
      <div v-else class="active-list">
        <article v-for="incident in incidents.filter(item => ['open', 'investigating'].includes(item.status))" :key="incident.id" class="active-item">
          <span class="active-severity" :class="incident.severity"><v-icon icon="mdi-alert-outline" size="17" /></span>
          <div><strong>{{ incident.title }}</strong><p>{{ incident.location }} · {{ incident.category.replaceAll('_', ' ') }} · {{ incident.severity }}</p></div>
          <span class="status-pill" :class="incident.status">{{ incident.status }}</span>
        </article>
      </div>
    </section>

    <section v-if="canReportIncident" class="section-card surface-card report-section" aria-labelledby="report-incident-heading">
      <div class="section-heading"><div><p class="eyebrow">EMPLOYEE REPORTING</p><h2 id="report-incident-heading">Report an incident</h2><p class="section-description">Your report is linked to your signed-in Northstar account.</p></div></div>
      <form class="incident-form" @submit.prevent="submitIncident">
        <label class="form-field"><span>Incident title</span><input v-model="reportForm.title" required minlength="5" maxlength="180" autocomplete="off" placeholder="Briefly describe the incident"></label>
        <label class="form-field"><span>Category</span><select v-model="reportForm.category" required><option disabled value="">Select category</option><option v-for="category in reportCategories" :key="category.value" :value="category.value">{{ category.label }}</option></select></label>
        <label class="form-field"><span>Severity</span><select v-model="reportForm.severity" required><option disabled value="">Select severity</option><option v-for="severity in severityOptions" :key="severity" :value="severity">{{ severity }}</option></select></label>
        <label class="form-field"><span>Location</span><input v-model="reportForm.location" required minlength="2" maxlength="500" placeholder="Building, site, or area"></label>
        <label class="form-field full-field"><span>Description</span><textarea v-model="reportForm.description" required minlength="10" maxlength="10000" rows="4" placeholder="Describe what happened and any immediate safety concerns"></textarea></label>
        <p v-if="formError" class="form-message error-message" role="alert">{{ formError }}</p>
        <p v-if="successMessage" class="form-message success-message" role="status">{{ successMessage }}</p>
        <div class="form-actions"><span>Submitted reports are visible according to Northstar incident access rules.</span><button class="submit-button" :disabled="submitting" type="submit">{{ submitting ? 'Submitting…' : 'Submit incident report' }}</button></div>
      </form>
    </section>

    <section class="section-card surface-card" aria-labelledby="incident-register-heading">
      <div class="section-heading register-heading">
        <div>
          <p class="eyebrow">INCIDENT REGISTER</p>
          <h2 id="incident-register-heading">Reported incidents</h2>
          <p class="section-description">Searchable incident records with severity, ownership, and status.</p>
        </div>
        <button class="details-button refresh-button" :disabled="loading" type="button" @click="loadIncidents">{{ loading ? 'Refreshing…' : 'Refresh' }}</button>
        <label class="search-field">
          <v-icon icon="mdi-magnify" size="18" />
          <input v-model="search" aria-label="Search incidents" placeholder="Search incidents" />
        </label>
      </div>
      <p v-if="loadError" class="table-message error-message" role="alert">{{ loadError }}</p>
      <div v-else-if="loading" class="table-message" aria-live="polite"><v-progress-circular indeterminate size="20" width="2" /> Loading incidents…</div>
      <div class="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Incident</th>
              <th>Category</th>
              <th>Location</th>
              <th>Severity</th>
              <th>Reported by</th>
              <th>Date reported</th>
              <th>Status</th>
              <th><span class="visually-hidden">Actions</span></th>
            </tr>
          </thead>
          <tbody v-if="!loading && !loadError && filteredIncidents.length === 0">
            <tr><td colspan="8">
              <div class="table-empty">
                <v-icon :icon="search ? 'mdi-magnify' : 'mdi-file-search-outline'" size="25" />
                <strong>{{ search ? 'No matching incidents' : 'No incident records available' }}</strong>
                <span>{{ search ? 'Try a different search term.' : 'No incidents are currently visible to your account.' }}</span>
              </div>
            </td></tr>
          </tbody>
          <tbody v-for="incident in filteredIncidents" v-else-if="!loading && !loadError" :key="incident.id">
            <tr>
              <td><strong class="incident-title">{{ incident.title }}</strong><small class="incident-description-preview">{{ incident.description }}</small></td>
              <td>{{ incident.category.replaceAll('_', ' ') }}</td>
              <td>{{ incident.location }}</td>
              <td><span class="severity-pill" :class="incident.severity">{{ incident.severity }}</span></td>
              <td>{{ incident.reported_by === auth.userId ? 'You' : 'Employee' }}</td>
              <td>{{ formatDate(incident.reported_at) }}</td>
              <td><span class="status-pill" :class="incident.status">{{ incident.status }}</span></td>
              <td><button class="details-button" type="button" @click="expandedIncidentId = expandedIncidentId === incident.id ? '' : incident.id">{{ expandedIncidentId === incident.id ? 'Hide details' : 'Details' }}</button></td>
            </tr>
            <tr v-if="expandedIncidentId === incident.id" class="detail-row">
              <td colspan="8">
                <div class="incident-detail">
                  <div class="incident-description"><p class="eyebrow">INCIDENT DESCRIPTION</p><p>{{ incident.description }}</p><p><strong>Reported:</strong> {{ formatDate(incident.reported_at) }} <span v-if="incident.assigned_responder"> · <strong>Responder:</strong> {{ employeeLabel(incident.assigned_responder) }}</span></p><p v-if="incident.resolution_details"><strong>Resolution:</strong> {{ incident.resolution_details }}</p></div>
                  <section class="history-section"><h3>Incident history</h3><p v-if="historyFor(incident.id).length === 0" class="history-empty">No updates are visible for this incident.</p><ol v-else class="history-list"><li v-for="update in historyFor(incident.id)" :key="update.id"><span class="history-dot" /><div><strong>{{ update.event_type.replaceAll('_', ' ') }}</strong><time>{{ formatDate(update.created_at) }}</time><p v-if="update.details">{{ update.details }}</p><small v-if="update.new_status">Status: {{ update.old_status ? `${update.old_status} → ` : '' }}{{ update.new_status }}</small><small v-if="update.new_severity">Severity: {{ update.old_severity ? `${update.old_severity} → ` : '' }}{{ update.new_severity }}</small><small v-if="update.event_type === 'responder_changed' || update.new_assigned_responder">Responder: {{ employeeLabel(update.new_assigned_responder) }}</small><small v-if="update.new_resolution_details">Resolution: {{ update.new_resolution_details }}</small></div></li></ol></section>
                  <section v-if="isDesignatedAdmin" class="admin-update-panel"><h3>Administrator incident controls</h3><label class="form-field"><span>Update visibility</span><select v-model="draftFor(incident).visibility"><option value="reporter">Reporter update</option><option value="response_team">Response team update</option><option value="admin">Private admin note</option></select></label><p v-if="draftFor(incident).visibility === 'admin'" class="private-note-hint">Private notes are visible only to the designated administrator and do not notify employees.</p><div class="admin-fields"><label class="form-field"><span>Status</span><select v-model="draftFor(incident).status" :disabled="draftFor(incident).visibility === 'admin'"><option v-for="status in statusOptions" :key="status" :value="status">{{ status }}</option></select></label><label class="form-field"><span>Severity</span><select v-model="draftFor(incident).severity" :disabled="draftFor(incident).visibility === 'admin'"><option v-for="severity in severityOptions" :key="severity" :value="severity">{{ severity }}</option></select></label><label class="form-field"><span>Assigned responder</span><select v-model="draftFor(incident).assignedResponder" :disabled="draftFor(incident).visibility === 'admin'"><option value="">Unassigned</option><option v-for="responder in responders" :key="responder.user_id" :value="responder.user_id">{{ `${responder.first_name} ${responder.last_name}`.trim() }}</option></select></label></div><label class="form-field"><span>Resolution details</span><textarea v-model="draftFor(incident).resolutionDetails" :disabled="draftFor(incident).visibility === 'admin'" maxlength="10000" rows="2" placeholder="Required when resolving or closing"></textarea></label><label class="form-field"><span>{{ draftFor(incident).visibility === 'admin' ? 'Private administrator note' : 'Update for the selected audience' }}</span><textarea v-model="draftFor(incident).update" maxlength="10000" rows="3" placeholder="Add useful response details"></textarea></label><p v-if="actionError" class="form-message error-message" role="alert">{{ actionError }}</p><p v-if="successMessage" class="form-message success-message" role="status">{{ successMessage }}</p><button class="submit-button" :disabled="savingIncidentId === incident.id" type="button" @click="saveIncidentUpdate(incident)">{{ savingIncidentId === incident.id ? 'Saving…' : 'Save update' }}</button></section>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="preparedness-section" aria-labelledby="preparedness-heading">
      <div class="section-heading">
        <div>
          <p class="eyebrow">READINESS</p>
          <h2 id="preparedness-heading">Preparedness resources</h2>
          <p class="section-description">Verified guidance and contacts for your organization.</p>
        </div>
      </div>
      <div class="resource-grid">
        <article v-for="resource in resourceItems" :key="resource.title" class="resource-card surface-card">
          <span class="resource-icon"><v-icon :icon="resource.icon" size="20" /></span>
          <div><h3>{{ resource.title }}</h3><p>{{ resource.description }}</p></div>
          <span class="not-configured">Not configured</span>
        </article>
      </div>
    </section>

    <footer class="dashboard-footer">
      <span><v-icon icon="mdi-information-outline" size="17" /> Incident visibility and management are enforced by Supabase Row Level Security and database functions.</span>
    </footer>
  </main>
</template>

<style scoped>
.disaster-dashboard { display: grid; gap: 22px; color: var(--ns-text-18352d, #18352d); }
.dashboard-header { display: flex; align-items: center; justify-content: space-between; gap: 20px; margin: 4px 0 2px; }
.heading-copy { display: flex; align-items: flex-start; gap: 12px; }
.heading-icon { display: grid; flex: 0 0 48px; width: 48px; height: 48px; place-items: center; border: 1px solid var(--ns-border-e6e9df, #e6e9df); border-radius: 14px; background: var(--ns-bg-fff, #fff); color: var(--ns-text-557262, #557262); }
.eyebrow { margin: 0 0 7px; color: var(--ns-text-71897b, #71897b); font: 9px "DM Mono", monospace; letter-spacing: 1.3px; }
.dashboard-header h1 { margin: 0; color: var(--ns-text-18352d, #18352d); font-size: clamp(25px, 3vw, 34px); letter-spacing: -1.2px; }
.intro, .section-description { margin: 7px 0 0; color: var(--ns-text-718178, #718178); font-size: 11px; line-height: 1.6; }
.connection-state { display: inline-flex; flex: 0 0 auto; align-items: center; gap: 8px; border: 1px solid var(--ns-border-eadcc4, #eadcc4); border-radius: 999px; padding: 9px 12px; background: var(--ns-bg-fffaf0, #fffaf0); color: var(--ns-text-856636, #856636); font-size: 10px; }
.connection-state span { width: 7px; height: 7px; border-radius: 50%; background: var(--ns-bg-d39c4c, #d39c4c); }
.connection-state.connected { border-color: var(--ns-border-d7e7d7, #d7e7d7); background: var(--ns-bg-f2f8f0, #f2f8f0); color: var(--ns-text-53785f, #53785f); }
.connection-state.connected span { background: var(--ns-bg-5b9669, #5b9669); }
.connection-state.failed { border-color: var(--ns-border-efd6d0, #efd6d0); background: var(--ns-bg-fff4f1, #fff4f1); color: var(--ns-text-a34c39, #a34c39); }
.connection-state.failed span { background: var(--ns-bg-c35f4a, #c35f4a); }
.overview-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 13px; }
.overview-card { min-width: 0; padding: 17px; border-radius: 12px; }
.overview-top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.overview-icon { display: grid; width: 35px; height: 35px; place-items: center; border-radius: 10px; }
.overview-icon.green { background: var(--ns-bg-edf4ed, #edf4ed); color: var(--ns-text-53785f, #53785f); }
.overview-icon.amber { background: var(--ns-bg-fbf3e4, #fbf3e4); color: var(--ns-text-a4792f, #a4792f); }
.overview-icon.blue { background: var(--ns-bg-edf2f8, #edf2f8); color: var(--ns-text-5a7192, #5a7192); }
.overview-icon.red { background: var(--ns-bg-f9ece9, #f9ece9); color: var(--ns-text-a85a49, #a85a49); }
.unavailable-tag { color: var(--ns-text-909b92, #909b92); font-size: 9px; }
.overview-card p { margin: 15px 0 2px; color: var(--ns-text-6d7b72, #6d7b72); font-size: 10px; }
.overview-card > strong { display: block; font-size: 27px; line-height: 1.2; }
.overview-card > small { display: block; margin-top: 6px; color: var(--ns-text-9aa49c, #9aa49c); font-size: 9px; line-height: 1.5; }
.section-card { overflow: hidden; border-radius: 12px; }
.section-heading { display: flex; align-items: center; justify-content: space-between; gap: 18px; padding: 19px 20px; }
.section-heading h2 { margin: 0; color: var(--ns-text-18352d, #18352d); font-size: 16px; letter-spacing: -.3px; }
.section-heading .eyebrow { margin-bottom: 6px; }
.section-count { flex: 0 0 auto; border: 1px solid var(--ns-border-e4e9e2, #e4e9e2); border-radius: 999px; padding: 6px 9px; color: var(--ns-text-78877d, #78877d); font-size: 9px; }
.empty-panel { display: flex; align-items: center; gap: 13px; margin: 0 20px 20px; border: 1px solid var(--ns-border-e9ede7, #e9ede7); border-radius: 10px; padding: 16px; background: var(--ns-bg-fafbf9, #fafbf9); }
.empty-icon { display: grid; flex: 0 0 40px; width: 40px; height: 40px; place-items: center; border-radius: 10px; background: var(--ns-bg-f1f3ee, #f1f3ee); color: var(--ns-text-78877d, #78877d); }
.empty-panel strong, .table-empty strong { color: var(--ns-text-364d40, #364d40); font-size: 11px; }
.empty-panel p { margin: 4px 0 0; color: var(--ns-text-78877d, #78877d); font-size: 10px; line-height: 1.5; }
.error-panel { border-color: var(--ns-border-efd6d0, #efd6d0); background: var(--ns-bg-fff8f6, #fff8f6); }
.inline-action { margin-top: 8px; border: 0; padding: 0; background: transparent; color: var(--ns-text-a34c39, #a34c39); font: inherit; font-weight: 700; cursor: pointer; }
.active-list { display: grid; gap: 0; margin: 0 20px 20px; border: 1px solid var(--ns-border-e9ede7, #e9ede7); border-radius: 10px; background: var(--ns-bg-fff, #fff); }
.active-item { display: flex; align-items: center; gap: 12px; padding: 12px 14px; }
.active-item + .active-item { border-top: 1px solid var(--ns-border-edf0e9, #edf0e9); }
.active-item > div { min-width: 0; flex: 1; }
.active-item strong { color: var(--ns-text-364d40, #364d40); font-size: 11px; }
.active-item p { margin: 4px 0 0; color: var(--ns-text-829187, #829187); font-size: 9px; text-transform: capitalize; }
.active-severity { display: grid; width: 34px; height: 34px; place-items: center; border-radius: 9px; background: var(--ns-bg-f1f3ee, #f1f3ee); color: var(--ns-text-718178, #718178); }
.active-severity.high, .active-severity.critical { background: var(--ns-bg-f9ece9, #f9ece9); color: var(--ns-text-a85a49, #a85a49); }
.incident-form { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 13px; padding: 0 20px 20px; }
.form-field { display: grid; min-width: 0; gap: 6px; color: var(--ns-text-52645a, #52645a); font-size: 10px; }
.form-field > span { font-weight: 700; }
.form-field input, .form-field select, .form-field textarea { width: 100%; min-height: 38px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); border-radius: 7px; padding: 9px 10px; background: var(--ns-bg-fff, #fff); color: var(--ns-text-30493b, #30493b); font: 11px "Manrope", sans-serif; }
.form-field textarea { resize: vertical; line-height: 1.55; }
.form-field input:focus, .form-field select:focus, .form-field textarea:focus { outline: 2px solid var(--ns-border-b8cba9, #b8cba9); outline-offset: 1px; }
.form-field :disabled { background: var(--ns-bg-f4f6f2, #f4f6f2); color: var(--ns-text-8b988e, #8b988e); }
.full-field { grid-column: 1 / -1; }
.form-message { grid-column: 1 / -1; margin: 0; font-size: 10px; line-height: 1.6; }
.error-message { color: var(--ns-text-a34c39, #a34c39); }
.success-message { color: var(--ns-text-47734f, #47734f); }
.form-actions { display: flex; grid-column: 1 / -1; align-items: center; justify-content: space-between; gap: 12px; }
.form-actions > span { color: var(--ns-text-829187, #829187); font-size: 9px; line-height: 1.5; }
.submit-button { min-height: 36px; border: 0; border-radius: 7px; padding: 0 13px; background: var(--ns-bg-18352d, #18352d); color: var(--ns-text-fff, #fff); font: 600 10px "Manrope", sans-serif; cursor: pointer; }
.submit-button:disabled { opacity: .6; cursor: wait; }
.table-message { display: flex; align-items: center; justify-content: center; gap: 9px; padding: 20px; color: var(--ns-text-718178, #718178); font-size: 10px; }
.table-message.error-message { display: block; padding-bottom: 0; }
.incident-title { display: block; max-width: 210px; color: var(--ns-text-364d40, #364d40); font-size: 10px; }
.incident-description-preview { display: block; overflow: hidden; max-width: 210px; margin-top: 4px; color: var(--ns-text-829187, #829187); font-size: 9px; text-overflow: ellipsis; white-space: nowrap; }
.severity-pill, .status-pill { display: inline-flex; border-radius: 999px; padding: 5px 8px; background: var(--ns-bg-f1f3ee, #f1f3ee); color: var(--ns-text-5e7064, #5e7064); font-size: 9px; text-transform: capitalize; white-space: nowrap; }
.severity-pill.high, .severity-pill.critical, .status-pill.open { background: var(--ns-bg-fff0eb, #fff0eb); color: var(--ns-text-a34c39, #a34c39); }
.severity-pill.medium, .status-pill.investigating { background: var(--ns-bg-fbf3e4, #fbf3e4); color: var(--ns-text-8a682f, #8a682f); }
.status-pill.resolved, .status-pill.closed, .severity-pill.low { background: var(--ns-bg-edf4ed, #edf4ed); color: var(--ns-text-53785f, #53785f); }
.details-button { border: 1px solid var(--ns-border-dce4d8, #dce4d8); border-radius: 6px; padding: 6px 8px; background: var(--ns-bg-fff, #fff); color: var(--ns-text-526c5c, #526c5c); font: 9px "Manrope", sans-serif; cursor: pointer; white-space: nowrap; }
.detail-row > td { padding: 0; background: var(--ns-bg-fbfcfa, #fbfcfa); }
.incident-detail { display: grid; gap: 18px; padding: 18px 20px; }
.incident-description > p:not(.eyebrow) { margin: 5px 0; color: var(--ns-text-65776b, #65776b); font-size: 10px; line-height: 1.65; white-space: pre-wrap; }
.history-section h3, .admin-update-panel h3 { margin: 0 0 11px; color: var(--ns-text-30493b, #30493b); font-size: 12px; }
.history-empty { color: var(--ns-text-829187, #829187); font-size: 10px; }
.history-list { display: grid; gap: 0; margin: 0; padding: 0; list-style: none; }
.history-list li { position: relative; display: flex; gap: 10px; padding: 0 0 13px; }
.history-list li:not(:last-child)::before { position: absolute; top: 9px; bottom: 0; left: 4px; width: 1px; background: var(--ns-bg-dce4d8, #dce4d8); content: ''; }
.history-dot { z-index: 1; flex: 0 0 9px; width: 9px; height: 9px; margin-top: 3px; border: 2px solid var(--ns-border-6f8c73, #6f8c73); border-radius: 50%; background: var(--ns-bg-fbfcfa, #fbfcfa); }
.history-list li > div { display: grid; gap: 4px; }
.history-list strong { color: var(--ns-text-40564a, #40564a); font-size: 10px; text-transform: capitalize; }
.history-list time, .history-list small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.history-list p { margin: 2px 0; color: var(--ns-text-65776b, #65776b); font-size: 10px; line-height: 1.55; white-space: pre-wrap; }
.admin-update-panel { display: grid; gap: 11px; border-top: 1px solid var(--ns-border-e4e9e2, #e4e9e2); padding-top: 16px; }
.admin-fields { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 11px; }
.private-note-hint { margin: -5px 0 0; color: var(--ns-text-829187, #829187); font-size: 9px; }
.register-heading { align-items: end; }
.search-field { display: flex; width: min(230px, 40%); height: 36px; align-items: center; gap: 7px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); border-radius: 7px; padding: 0 10px; color: var(--ns-text-8b988e, #8b988e); }
.search-field input { width: 100%; min-width: 0; border: 0; outline: 0; background: transparent; color: var(--ns-text-718178, #718178); font: 10px "Manrope", sans-serif; }
.table-scroll { overflow-x: auto; }
table { width: 100%; min-width: 820px; border-collapse: collapse; text-align: left; }
th { padding: 11px 14px; border-top: 1px solid var(--ns-border-edf0e9, #edf0e9); border-bottom: 1px solid var(--ns-border-edf0e9, #edf0e9); background: var(--ns-bg-fafbf9, #fafbf9); color: var(--ns-text-829187, #829187); font: 8px "DM Mono", monospace; letter-spacing: .4px; text-transform: uppercase; white-space: nowrap; }
th:first-child { padding-left: 20px; }
.table-empty { display: grid; min-height: 142px; place-content: center; justify-items: center; gap: 7px; padding: 20px; color: var(--ns-text-98a49b, #98a49b); text-align: center; }
.table-empty span { max-width: 440px; color: var(--ns-text-829187, #829187); font-size: 10px; line-height: 1.6; }
.preparedness-section { display: grid; gap: 13px; }
.preparedness-section > .section-heading { padding: 0 2px; }
.resource-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 13px; }
.resource-card { display: grid; grid-template-columns: 36px minmax(0, 1fr); align-items: start; gap: 11px; border-radius: 11px; padding: 16px; }
.resource-icon { display: grid; width: 35px; height: 35px; place-items: center; border-radius: 9px; background: var(--ns-bg-f0f4ec, #f0f4ec); color: var(--ns-text-617a68, #617a68); }
.resource-card h3 { margin: 2px 0 5px; color: var(--ns-text-30493b, #30493b); font-size: 11px; }
.resource-card p { min-height: 32px; margin: 0; color: var(--ns-text-829187, #829187); font-size: 9px; line-height: 1.6; }
.not-configured { grid-column: 2; justify-self: start; margin-top: 3px; color: var(--ns-text-9a825d, #9a825d); font-size: 9px; }
.dashboard-footer { display: flex; align-items: center; justify-content: space-between; gap: 16px; border-top: 1px solid var(--ns-border-e1e7de, #e1e7de); padding: 14px 2px 0; color: var(--ns-text-829187, #829187); font-size: 9px; line-height: 1.6; }
.dashboard-footer > span { display: flex; align-items: center; gap: 7px; }
.dashboard-footer a { display: inline-flex; flex: 0 0 auto; align-items: center; gap: 4px; color: var(--ns-text-526c5c, #526c5c); text-decoration: none; }
.dashboard-footer a:hover { color: var(--ns-text-18352d, #18352d); }
.visually-hidden { position: absolute; overflow: hidden; width: 1px; height: 1px; clip: rect(0, 0, 0, 0); white-space: nowrap; }
@media (max-width: 1000px) { .overview-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (max-width: 700px) {
  .disaster-dashboard { gap: 16px; }
  .dashboard-header { align-items: flex-start; flex-direction: column; }
  .connection-state { margin-left: 63px; }
  .section-heading { align-items: flex-start; }
  .register-heading { flex-direction: column; }
  .search-field { width: 100%; }
  .resource-grid { grid-template-columns: 1fr; }
  .dashboard-footer { align-items: flex-start; flex-direction: column; }
  .incident-form, .admin-fields { grid-template-columns: 1fr; }
  .full-field, .form-message, .form-actions { grid-column: auto; }
  .form-actions { align-items: flex-start; flex-direction: column; }
  .active-list { margin-right: 12px; margin-left: 12px; }
}
@media (max-width: 420px) {
  .overview-grid { grid-template-columns: 1fr 1fr; gap: 9px; }
  .overview-card { padding: 12px; }
  .overview-card > strong { font-size: 23px; }
  .unavailable-tag { font-size: 8px; }
  .heading-copy { gap: 10px; }
  .heading-icon { flex-basis: 40px; width: 40px; height: 40px; }
  .connection-state { margin-left: 50px; }
  .empty-panel { align-items: flex-start; margin-right: 12px; margin-left: 12px; padding: 12px; }
}
</style>
