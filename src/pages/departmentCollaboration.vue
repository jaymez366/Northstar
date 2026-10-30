<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import NorthstarBackButton from '@/components/NorthstarBackButton.vue'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

type Department = { id: string, name: string }
type DiscussionPost = { id: string, department_id: string, author_id: string, parent_id: string | null, content: string, created_at: string, author?: { first_name: string | null, last_name: string | null } | { first_name: string | null, last_name: string | null }[] | null }
type Incident = { id: string, title: string, description: string, category: string, severity: string, location: string, reported_by: string | null, reporter_name: string | null, reported_at: string, status: string, assigned_responder: string | null, resolution_details: string | null, department_id: string, deleted_at: string | null, is_reporter: boolean }
type EventRow = { id: string, title: string, description: string | null, location: string | null, start_time: string, end_time: string | null, department_id: string }
type ResourceRow = { id: string, title: string, description: string | null, category: string, storage_path: string, department_id: string }

const auth = useAuthStore()
const departments = ref<Department[]>([])
const selectedDepartmentId = ref('')
const posts = ref<DiscussionPost[]>([])
const incidents = ref<Incident[]>([])
const events = ref<EventRow[]>([])
const resources = ref<ResourceRow[]>([])
const tab = ref('Overview')
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const success = ref('')
const discussionDraft = ref('')
const announcementDraft = ref({ title: '', content: '' })
const eventDraft = ref({ title: '', description: '', location: '', start: '', end: '' })
const editingEventId = ref('')
const resourceDraft = ref({ title: '', description: '', category: '' })
const editingResourceId = ref('')
const selectedFile = ref<File | null>(null)
const tabs = ['Overview', 'Announcements', 'Discussions', 'Events', 'Resources', 'Disaster Reports']
const isHead = computed(() => auth.profile.departmentLevel === 1)
const canManage = computed(() => auth.isAdmin || (isHead.value && Boolean(selectedDepartmentId.value)))
const currentDepartment = computed(() => departments.value.find(item => item.id === selectedDepartmentId.value))
const discussionAuthor = (post: DiscussionPost) => {
  const author = Array.isArray(post.author) ? post.author[0] : post.author
  return `${author?.first_name ?? ''} ${author?.last_name ?? ''}`.trim() || 'Department member'
}

async function loadDepartments () {
  if (!supabase) return
  if (auth.isAdmin) {
    const { data, error: queryError } = await supabase.rpc('northstar_admin_list_department_assignments')
    if (queryError) throw queryError
    const rows = (data ?? []) as { department_id: string | null, department_name: string | null }[]
    const departmentRows = rows.filter((row): row is { department_id: string, department_name: string } => Boolean(row.department_id && row.department_name))
    departments.value = [...new Map<string, Department>(departmentRows.map(row => [row.department_id, { id: row.department_id, name: row.department_name }])).values()]
    selectedDepartmentId.value ||= departments.value[0]?.id ?? ''
  } else if (auth.profile.departmentId && auth.profile.departmentLevel) {
    const { data, error: queryError } = await supabase.from('departments').select('id,name').eq('id', auth.profile.departmentId).maybeSingle()
    if (queryError) throw queryError
    if (data) {
      departments.value = [data]
      selectedDepartmentId.value = data.id
    }
  }
}

async function load () {
  error.value = ''
  success.value = ''
  if (!supabase || !isSupabaseConfigured) {
    error.value = 'Department collaboration requires a configured NorthStar Supabase connection.'
    return
  }
  loading.value = true
  try {
    await loadDepartments()
    if (!selectedDepartmentId.value) {
      posts.value = []; incidents.value = []; events.value = []; resources.value = []
      return
    }
    const departmentId = selectedDepartmentId.value
    const results = await Promise.all([
      supabase.from('northstar_department_discussion_posts').select('id,department_id,author_id,parent_id,content,created_at,author:profiles!northstar_department_discussion_posts_author_id_fkey(first_name,last_name)').eq('department_id', departmentId).order('created_at', { ascending: false }),
      supabase.from('events').select('id,title,description,location,start_time,end_time,department_id').eq('department_id', departmentId).order('start_time'),
      supabase.from('resources').select('id,title,description,category,storage_path,department_id').eq('department_id', departmentId).order('created_at', { ascending: false }),
      supabase.rpc('northstar_department_list_incidents'),
      supabase.from('announcements').select('id,title,content,author_id,department_id,created_at').eq('department_id', departmentId).order('created_at', { ascending: false }),
    ])
    const failure = results.find(result => result.error)?.error
    if (failure) throw failure
    posts.value = (results[0].data ?? []) as DiscussionPost[]
    events.value = results[1].data ?? []
    resources.value = results[2].data ?? []
    incidents.value = (results[3].data ?? []).filter((item: Incident) => item.department_id === departmentId)
    announcements.value = results[4].data ?? []
  } catch (reason) {
    error.value = `Could not load department collaboration: ${reason instanceof Error ? reason.message : 'Request failed.'}`
  } finally {
    loading.value = false
  }
}

const announcements = ref<{ id: string, title: string, content: string, author_id: string, department_id: string, created_at: string }[]>([])

async function publishDiscussion () {
  if (!supabase || !auth.userId || !selectedDepartmentId.value || !discussionDraft.value.trim() || saving.value) return
  saving.value = true; error.value = ''; success.value = ''
  const { error: insertError } = await supabase.from('northstar_department_discussion_posts').insert({ department_id: selectedDepartmentId.value, author_id: auth.userId, content: discussionDraft.value.trim() })
  saving.value = false
  if (insertError) { error.value = `Could not publish discussion post: ${insertError.message}`; return }
  discussionDraft.value = ''; success.value = 'Discussion post published.'; await load()
}

async function publishAnnouncement () {
  if (!supabase || !auth.userId || !canManage.value || !announcementDraft.value.title.trim() || !announcementDraft.value.content.trim() || saving.value) return
  saving.value = true; error.value = ''; success.value = ''
  const { error: insertError } = await supabase.from('announcements').insert({ title: announcementDraft.value.title.trim(), content: announcementDraft.value.content.trim(), author_id: auth.userId, department_id: selectedDepartmentId.value, priority: 'normal' })
  saving.value = false
  if (insertError) { error.value = `Could not publish announcement: ${insertError.message}`; return }
  announcementDraft.value = { title: '', content: '' }; success.value = 'Department announcement published.'; await load()
}

async function deleteAnnouncement (item: typeof announcements.value[number]) {
  if (!supabase || !canManage.value || !window.confirm(`Delete announcement “${item.title}”?`)) return
  const { error: deleteError } = await supabase.from('announcements').delete().eq('id', item.id)
  if (deleteError) { error.value = `Could not delete announcement: ${deleteError.message}`; return }
  success.value = 'Announcement deleted.'; await load()
}

async function createEvent () {
  if (!supabase || !auth.userId || !canManage.value || !eventDraft.value.title.trim() || !eventDraft.value.start || saving.value) return
  const start = new Date(eventDraft.value.start); const end = eventDraft.value.end ? new Date(eventDraft.value.end) : null
  if (!Number.isFinite(start.getTime()) || (end && (!Number.isFinite(end.getTime()) || end <= start))) { error.value = 'Check the event start and end times.'; return }
  saving.value = true; error.value = ''; success.value = ''
  const eventValues = { title: eventDraft.value.title.trim(), description: eventDraft.value.description.trim() || null, location: eventDraft.value.location.trim() || null, start_time: start.toISOString(), end_time: end?.toISOString() ?? null }
  const result = editingEventId.value
    ? await supabase.from('events').update(eventValues).eq('id', editingEventId.value)
    : await supabase.from('events').insert({ ...eventValues, organizer_id: auth.userId, department_id: selectedDepartmentId.value })
  saving.value = false
  if (result.error) { error.value = `Could not ${editingEventId.value ? 'update' : 'create'} event: ${result.error.message}`; return }
  const wasEditing = Boolean(editingEventId.value)
  editingEventId.value = ''
  eventDraft.value = { title: '', description: '', location: '', start: '', end: '' }; success.value = wasEditing ? 'Department event updated.' : 'Department event created.'; await load()
}

function editEvent (event: EventRow) {
  editingEventId.value = event.id
  eventDraft.value = {
    title: event.title,
    description: event.description ?? '',
    location: event.location ?? '',
    start: new Date(event.start_time).toISOString().slice(0, 16),
    end: event.end_time ? new Date(event.end_time).toISOString().slice(0, 16) : '',
  }
  tab.value = 'Events'
}

async function uploadResource () {
  const file = selectedFile.value
  if (!supabase || !auth.userId || !canManage.value || !resourceDraft.value.title.trim() || !resourceDraft.value.category.trim() || saving.value) return
  if (!editingResourceId.value && !file) { error.value = 'Choose a file to upload.'; return }
  if (file && file.size > 50 * 1024 * 1024) { error.value = 'Choose a file no larger than 50 MB.'; return }
  saving.value = true; error.value = ''; success.value = ''
  if (editingResourceId.value) {
    const { error: updateError } = await supabase.from('resources').update({ title: resourceDraft.value.title.trim(), description: resourceDraft.value.description.trim() || null, category: resourceDraft.value.category.trim() }).eq('id', editingResourceId.value)
    saving.value = false
    if (updateError) { error.value = `Could not update resource: ${updateError.message}`; return }
    editingResourceId.value = ''; resourceDraft.value = { title: '', description: '', category: '' }; success.value = 'Department resource updated.'; await load(); return
  }
  const safeName = file!.name.normalize('NFKD').replace(/[^\w.-]+/g, '-').slice(-100) || 'resource'
  const path = `departments/${selectedDepartmentId.value}/resources/${crypto.randomUUID()}-${safeName}`
  const { error: uploadError } = await supabase.storage.from('company-resources').upload(path, file!, { upsert: false, ...(file?.type ? { contentType: file.type } : {}) })
  if (uploadError) { saving.value = false; error.value = `Could not upload department resource: ${uploadError.message}`; return }
  const { error: insertError } = await supabase.from('resources').insert({ title: resourceDraft.value.title.trim(), description: resourceDraft.value.description.trim() || null, category: resourceDraft.value.category.trim(), storage_path: path, uploaded_by: auth.userId, department_id: selectedDepartmentId.value })
  if (insertError) {
    const { error: cleanupError } = await supabase.storage.from('company-resources').remove([path])
    saving.value = false
    error.value = `Could not save resource metadata: ${insertError.message}${cleanupError ? ` The unused upload could not be removed: ${cleanupError.message}` : ''}`
    return
  }
  saving.value = false; resourceDraft.value = { title: '', description: '', category: '' }; selectedFile.value = null; success.value = 'Department resource uploaded.'; await load()
}

async function downloadResource (resource: ResourceRow) {
  if (!supabase) return
  error.value = ''
  const { data, error: linkError } = await supabase.storage.from('company-resources').createSignedUrl(resource.storage_path, 60)
  if (linkError) { error.value = `Could not prepare the download: ${linkError.message}`; return }
  window.open(data.signedUrl, '_blank', 'noopener,noreferrer')
}

async function deleteResource (resource: ResourceRow) {
  if (!supabase || !canManage.value || !window.confirm(`Delete “${resource.title}” and its stored file?`)) return
  error.value = ''
  const { error: rowError } = await supabase.from('resources').delete().eq('id', resource.id)
  if (rowError) { error.value = `Could not delete resource metadata: ${rowError.message}`; return }
  const { error: fileError } = await supabase.storage.from('company-resources').remove([resource.storage_path])
  if (fileError) error.value = `Resource record was deleted, but its file could not be removed: ${fileError.message}`
  await load()
}

function editResource (resource: ResourceRow) {
  editingResourceId.value = resource.id
  resourceDraft.value = { title: resource.title, description: resource.description ?? '', category: resource.category }
  selectedFile.value = null
  tab.value = 'Resources'
}

async function deleteEvent (event: EventRow) {
  if (!supabase || !canManage.value || !window.confirm(`Delete event “${event.title}”?`)) return
  const { error: deleteError } = await supabase.from('events').delete().eq('id', event.id)
  if (deleteError) { error.value = `Could not delete event: ${deleteError.message}`; return }
  success.value = 'Event deleted.'; await load()
}

onMounted(() => { void load() })
</script>

<template>
  <main class="department-space">
    <header class="page-heading"><div class="heading-main"><NorthstarBackButton /><div><p class="eyebrow">NORTHSTAR DEPARTMENT SPACE</p><h1>{{ currentDepartment?.name || 'Department collaboration' }}</h1><p>{{ auth.isAdmin ? 'Organisation-wide oversight' : isHead ? 'Department Head · Level 1' : `Department member${auth.profile.departmentLevel ? ` · Level ${auth.profile.departmentLevel}` : ''}` }}</p></div></div><div class="heading-actions"><select v-if="auth.isAdmin" v-model="selectedDepartmentId" aria-label="Choose department" @change="load"><option v-for="department in departments" :key="department.id" :value="department.id">{{ department.name }}</option></select><button class="secondary-action" type="button" :disabled="loading" @click="load">{{ loading ? 'Refreshing…' : 'Refresh' }}</button></div></header>
    <p v-if="error" class="error-message" role="alert">{{ error }}</p><p v-if="success" class="success-message" role="status">{{ success }}</p>
    <div v-if="!auth.isAdmin && (!auth.profile.departmentLevel || !auth.profile.departmentId)" class="surface-card assignment-needed"><h2>Department access is not assigned</h2><p>Ask the designated administrator to assign your department and level. Department collaboration stays unavailable until then.</p></div>
    <template v-else-if="selectedDepartmentId">
      <nav class="department-tabs" aria-label="Department sections"><button v-for="item in tabs" :key="item" type="button" :aria-current="tab === item ? 'page' : undefined" @click="tab = item">{{ item }}</button></nav>
      <section v-if="tab === 'Overview'" class="overview-grid">
        <button v-for="item in tabs.slice(1)" :key="item" class="surface-card overview-tile" type="button" @click="tab = item"><span>{{ item }}</span><strong>{{ item === 'Announcements' ? announcements.length : item === 'Discussions' ? posts.length : item === 'Events' ? events.length : item === 'Resources' ? resources.length : incidents.length }}</strong><small>Open department section <v-icon icon="mdi-arrow-right" size="14" /></small></button>
      </section>
      <section v-else-if="tab === 'Announcements'" class="surface-card content-panel">
        <h2>Announcements</h2><form v-if="canManage" class="inline-form" @submit.prevent="publishAnnouncement"><label>Title<input v-model="announcementDraft.title" maxlength="180" required></label><label>Message<textarea v-model="announcementDraft.content" maxlength="10000" required rows="3" /></label><button class="primary-action" :disabled="saving">Publish announcement</button></form>
        <article v-for="item in announcements" :key="item.id" class="content-row manage-row"><div><strong>{{ item.title }}</strong><p>{{ item.content }}</p><small>{{ new Date(item.created_at).toLocaleString() }}</small></div><button v-if="canManage" class="secondary-action" type="button" @click="deleteAnnouncement(item)">Delete</button></article><p v-if="!announcements.length" class="empty">No department announcements yet.</p>
      </section>
      <section v-else-if="tab === 'Discussions'" class="surface-card content-panel"><h2>Department discussions</h2><form class="inline-form" @submit.prevent="publishDiscussion"><label>Share with your department<textarea v-model="discussionDraft" maxlength="10000" rows="3" required /></label><button class="primary-action" :disabled="saving">Post to discussion</button></form><article v-for="post in posts" :key="post.id" class="content-row"><strong>{{ discussionAuthor(post) }}</strong><p>{{ post.content }}</p><small>{{ new Date(post.created_at).toLocaleString() }}</small></article><p v-if="!posts.length" class="empty">No discussion posts yet. Start the conversation.</p></section>
      <section v-else-if="tab === 'Events'" class="surface-card content-panel"><h2>Department events</h2><form v-if="canManage" class="form-grid" @submit.prevent="createEvent"><label>Title<input v-model="eventDraft.title" maxlength="180" required></label><label>Start<input v-model="eventDraft.start" type="datetime-local" required></label><label>End<input v-model="eventDraft.end" type="datetime-local"></label><label>Location<input v-model="eventDraft.location" maxlength="500"></label><label class="wide">Description<textarea v-model="eventDraft.description" maxlength="10000" rows="2" /></label><button class="primary-action" :disabled="saving">{{ editingEventId ? 'Save event' : 'Create event' }}</button><button v-if="editingEventId" class="secondary-action" type="button" @click="editingEventId = ''; eventDraft = { title: '', description: '', location: '', start: '', end: '' }">Cancel edit</button></form><article v-for="event in events" :key="event.id" class="content-row manage-row"><div><strong>{{ event.title }}</strong><p>{{ event.description || 'No description provided.' }}</p><small>{{ new Date(event.start_time).toLocaleString() }} · {{ event.location || 'Location to be announced' }}</small></div><div v-if="canManage" class="button-row"><button class="secondary-action" type="button" @click="editEvent(event)">Edit</button><button class="secondary-action" type="button" @click="deleteEvent(event)">Delete</button></div></article><p v-if="!events.length" class="empty">No department events yet.</p></section>
      <section v-else-if="tab === 'Resources'" class="surface-card content-panel"><h2>Department resources</h2><form v-if="canManage" class="form-grid" @submit.prevent="uploadResource"><label>Title<input v-model="resourceDraft.title" maxlength="180" required></label><label>Category<input v-model="resourceDraft.category" maxlength="100" required></label><label class="wide">Description<textarea v-model="resourceDraft.description" maxlength="10000" rows="2" /></label><label class="wide">File<input type="file" :required="!editingResourceId" @change="selectedFile = ($event.target as HTMLInputElement).files?.[0] ?? null"></label><small class="wide">Maximum file size: 50 MB. Files remain in the private company-resources bucket.</small><button class="primary-action" :disabled="saving">{{ editingResourceId ? 'Save resource' : 'Upload resource' }}</button><button v-if="editingResourceId" class="secondary-action" type="button" @click="editingResourceId = ''; resourceDraft = { title: '', description: '', category: '' }">Cancel edit</button></form><article v-for="resource in resources" :key="resource.id" class="content-row manage-row"><div><strong>{{ resource.title }}</strong><p>{{ resource.description || resource.category }}</p><small>{{ resource.category }}</small></div><div class="button-row"><button class="secondary-action" type="button" @click="downloadResource(resource)">Download</button><button v-if="canManage" class="secondary-action" type="button" @click="editResource(resource)">Edit</button><button v-if="canManage" class="secondary-action" type="button" @click="deleteResource(resource)">Delete</button></div></article><p v-if="!resources.length" class="empty">No department resources yet.</p></section>
      <section v-else class="surface-card content-panel"><h2>Department disaster reports</h2><p>{{ incidents.length }} reports are available under your department permissions. Reporter editing, history, resolution, and status controls stay in the existing Disaster Management workflow.</p><router-link class="primary-action" to="/disaster-management">Open Disaster Management <v-icon icon="mdi-arrow-right" size="15" /></router-link></section>
    </template>
    <div v-else-if="!loading" class="surface-card assignment-needed"><h2>No departments are available</h2><p>Department records could not be found for this account.</p></div>
  </main>
</template>

<style scoped>
.department-space { color: var(--ns-text-primary, #18352d); }
.page-heading, .heading-main, .heading-actions { display: flex; align-items: center; gap: 12px; }
.page-heading { justify-content: space-between; margin-bottom: 18px; }
.page-heading h1 { margin: 4px 0; font-size: 25px; }.page-heading p { color: var(--ns-text-secondary, #718178); }
.eyebrow { font: 10px "DM Mono", monospace; letter-spacing: 1px; }.heading-actions select { min-height: 38px; border: 1px solid var(--ns-border); border-radius: 5px; padding: 7px; background: white; }
.department-tabs { display: flex; flex-wrap: wrap; gap: 5px; margin-bottom: 14px; border-bottom: 1px solid var(--ns-border); }.department-tabs button { border: 0; border-bottom: 2px solid transparent; padding: 10px 12px; background: transparent; color: var(--ns-text-secondary); cursor: pointer; font: 600 11px Manrope, sans-serif; }.department-tabs button[aria-current="page"] { border-color: #2877c7; color: #1c66ad; }
.overview-grid { display: grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap: 12px; }.overview-tile { display: grid; gap: 9px; padding: 18px; color: inherit; text-align: left; cursor: pointer; }.overview-tile strong { color: #246eb4; font-size: 28px; }.overview-tile small { color: var(--ns-text-secondary); }
.content-panel { display: grid; gap: 12px; padding: 18px; }.content-panel h2, h2 { margin: 0; font-size: 17px; }.content-row { display: grid; gap: 5px; border-top: 1px solid var(--ns-border); padding: 13px 2px; }.content-row p { margin: 0; color: var(--ns-text-secondary); white-space: pre-wrap; }.content-row small, .empty { color: var(--ns-text-secondary); font-size: 10px; }.inline-form, .form-grid { display: grid; gap: 11px; padding: 14px; }.inline-form label, .form-grid label { display: grid; gap: 5px; color: var(--ns-text-secondary); font-size: 11px; }.inline-form input, .inline-form textarea, .inline-form select, .form-grid input, .form-grid textarea, .form-grid select { width: 100%; min-height: 38px; border: 1px solid var(--ns-border); border-radius: 5px; padding: 8px 10px; background: var(--ns-surface-raised, #fff); color: var(--ns-text-primary, #18352d); font: inherit; }.form-grid { grid-template-columns: repeat(2,minmax(0,1fr)); }.wide { grid-column: 1/-1; }.manage-row { grid-template-columns: 1fr auto; align-items: center; }.button-row { display: flex; gap: 7px; }.incident-update { margin-top: 10px; border-top: 1px dashed var(--ns-border); }.status-pill { margin-left: 5px; color: #246eb4; font-size: 10px; }.assignment-needed { padding: 24px; }.assignment-needed p, .error-message { color: #a34c39; }.success-message { color: #23724a; }
@media(max-width:700px) { .overview-grid { grid-template-columns: 1fr 1fr; }.page-heading { align-items: flex-start; flex-direction: column; }.heading-actions { width: 100%; justify-content: flex-end; }.form-grid { grid-template-columns: 1fr; }.wide { grid-column: auto; } }
</style>
