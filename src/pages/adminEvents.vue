<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import NorthstarBackButton from '@/components/NorthstarBackButton.vue'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

type EventRecord = {
  id: string
  title: string
  description: string | null
  location: string | null
  start_time: string
  end_time: string | null
  organizer_id: string
  organizer: { first_name: string | null; last_name: string | null } | { first_name: string | null; last_name: string | null }[] | null
  department_id: string | null
  created_at: string
  updated_at: string
}

const auth = useAuthStore()
const rows = ref<EventRecord[]>([])
const loading = ref(false)
const createDialog = ref(false)
const createLoading = ref(false)
const createError = ref('')
const createSuccess = ref('')
const selectedEvent = ref<EventRecord | null>(null)
const eventForm = ref({ title: '', description: '', location: '', startTime: '', endTime: '' })
const error = ref('')
const search = ref('')
const events = computed(() => rows.value.filter(event =>
  `${event.title} ${event.description ?? ''} ${event.location ?? ''}`.toLowerCase().includes(search.value.trim().toLowerCase())))

async function loadEvents () {
  if (!auth.isAuthenticated || !auth.isAdmin) return
  if (!isSupabaseConfigured || !supabase) {
    error.value = 'Northstar Supabase is not configured.'
    return
  }
  loading.value = true
  error.value = ''
  const { data, error: queryError } = await supabase.from('events')
    .select('id,title,description,location,start_time,end_time,organizer_id,department_id,created_at,updated_at,organizer:profiles!events_organizer_id_fkey(first_name,last_name)')
    .order('start_time', { ascending: true })
  loading.value = false
  if (queryError) {
    error.value = `Could not load events: ${queryError.message}`
    return
  }
  rows.value = data ?? []
}

function resetEventForm () {
  eventForm.value = { title: '', description: '', location: '', startTime: '', endTime: '' }
  createError.value = ''
}

async function createEvent () {
  if (createLoading.value) return
  if (!auth.isAuthenticated || !auth.isAdmin || !auth.userId || !supabase) {
    createError.value = 'A signed-in Northstar administrator and Supabase connection are required.'
    return
  }

  const title = eventForm.value.title.trim()
  const startTime = new Date(eventForm.value.startTime)
  const endTime = eventForm.value.endTime ? new Date(eventForm.value.endTime) : null
  if (!title || !Number.isFinite(startTime.getTime())) {
    createError.value = 'Enter an event title and a valid start date and time.'
    return
  }
  if (endTime && (!Number.isFinite(endTime.getTime()) || endTime <= startTime)) {
    createError.value = 'The end time must be later than the start time.'
    return
  }

  createLoading.value = true
  createError.value = ''
  createSuccess.value = ''
  const { error: insertError } = await supabase.from('events').insert({
    title,
    description: eventForm.value.description.trim() || null,
    location: eventForm.value.location.trim() || null,
    start_time: startTime.toISOString(),
    end_time: endTime?.toISOString() ?? null,
    organizer_id: auth.userId,
    department_id: null,
  })
  createLoading.value = false

  if (insertError) {
    createError.value = `Could not create event: ${insertError.message}`
    return
  }

  createDialog.value = false
  resetEventForm()
  createSuccess.value = 'Event created.'
  await loadEvents()
}

const formatDate = (value: string) => new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
const organizerName = (event: EventRecord) => {
  const organizer = Array.isArray(event.organizer) ? event.organizer[0] : event.organizer
  return `${organizer?.first_name ?? ''} ${organizer?.last_name ?? ''}`.trim() || 'Name unavailable'
}
onMounted(() => { void loadEvents() })
</script>

<template>
  <main class="admin-management">
    <header class="page-heading">
      <div class="heading-main"><NorthstarBackButton /><div><p class="eyebrow">ADMINISTRATION</p><h1>Event Management</h1><p>Review scheduled company events and their current details.</p></div></div>
      <div class="heading-actions"><button class="secondary-action" :disabled="loading" type="button" @click="loadEvents">{{ loading ? 'Refreshing…' : 'Refresh' }}</button><button class="primary-action" type="button" @click="createDialog = true; resetEventForm()"><v-icon icon="mdi-plus" size="17" /> Create Event</button></div>
    </header>
    <p v-if="createSuccess" class="success" role="status">{{ createSuccess }}</p>
    <section class="surface-card management-panel">
      <div class="toolbar"><input v-model="search" class="field-control" aria-label="Search events" placeholder="Search events"><span>{{ events.length }} events</span></div>
      <p v-if="error" class="error" role="alert">{{ error }}</p>
      <p v-else-if="loading" role="status">Loading events…</p>
      <div v-else-if="events.length" class="record-list">
        <article v-for="event in events" :key="event.id" class="record">
          <div><h2>{{ event.title }}</h2><p>{{ event.description || 'No description provided.' }}</p><small>{{ event.location || 'Location to be announced' }}</small></div>
          <dl><div><dt>Starts</dt><dd>{{ formatDate(event.start_time) }}</dd></div><div><dt>Ends</dt><dd>{{ event.end_time ? formatDate(event.end_time) : 'Not specified' }}</dd></div><div><dt>Organizer</dt><dd>{{ organizerName(event) }}</dd></div></dl>
          <button class="secondary-action event-details-button" type="button" @click="selectedEvent = event">View event</button>
        </article>
      </div>
      <p v-else>No events are currently available.</p>
      <p class="permission-note">Event reads and writes remain subject to the existing Supabase Row Level Security policies.</p>
    </section>

    <v-dialog v-model="createDialog" max-width="600">
      <v-card class="event-form-dialog">
        <v-card-title class="dialog-title"><span>Create event</span><v-btn aria-label="Close event form" icon="mdi-close" size="small" variant="text" @click="createDialog = false" /></v-card-title>
        <form @submit.prevent="createEvent">
          <v-card-text class="event-form-fields">
            <label class="form-field"><span>Event title</span><input v-model="eventForm.title" autocomplete="off" maxlength="180" required></label>
            <label class="form-field"><span>Description</span><textarea v-model="eventForm.description" maxlength="10000" rows="3" /></label>
            <label class="form-field"><span>Start date and time</span><input v-model="eventForm.startTime" type="datetime-local" required></label>
            <label class="form-field"><span>End date and time (optional)</span><input v-model="eventForm.endTime" type="datetime-local"></label>
            <label class="form-field"><span>Location or meeting link</span><input v-model="eventForm.location" maxlength="500"></label>
            <p class="form-note">The signed-in administrator will be recorded as organizer. Event access and writes remain subject to the existing Supabase policies.</p>
            <p v-if="createError" class="error" role="alert">{{ createError }}</p>
          </v-card-text>
          <v-card-actions><v-spacer /><v-btn variant="text" :disabled="createLoading" @click="createDialog = false">Cancel</v-btn><v-btn color="primary" type="submit" :disabled="createLoading" :loading="createLoading">{{ createLoading ? 'Creating…' : 'Create Event' }}</v-btn></v-card-actions>
        </form>
      </v-card>
    </v-dialog>

    <v-dialog :model-value="selectedEvent !== null" max-width="560" @update:model-value="!$event && (selectedEvent = null)">
      <v-card v-if="selectedEvent" class="event-form-dialog">
        <v-card-title>{{ selectedEvent.title }}</v-card-title>
        <v-card-subtitle>{{ formatDate(selectedEvent.start_time) }}</v-card-subtitle>
        <v-card-text><p>{{ selectedEvent.description || 'No description provided.' }}</p><dl class="event-detail-list"><div><dt>Ends</dt><dd>{{ selectedEvent.end_time ? formatDate(selectedEvent.end_time) : 'Not specified' }}</dd></div><div><dt>Location</dt><dd>{{ selectedEvent.location || 'Location to be announced' }}</dd></div><div><dt>Organizer</dt><dd>{{ organizerName(selectedEvent) }}</dd></div></dl></v-card-text>
        <v-card-actions><v-spacer /><v-btn variant="text" @click="selectedEvent = null">Close</v-btn></v-card-actions>
      </v-card>
    </v-dialog>
  </main>
</template>

<style scoped>
.admin-management { color: var(--ns-text-18352d, #18352d); }
.page-heading { display: flex; justify-content: space-between; align-items: center; gap: 16px; margin-bottom: 20px; }
.heading-main, .heading-actions { display: flex; align-items: center; gap: 12px; }
.heading-actions { flex: 0 0 auto; }
.page-heading h1 { margin: 4px 0; font-size: 26px; }
.page-heading p { color: var(--ns-text-718178, #718178); }
.eyebrow { font: 10px "DM Mono", monospace; letter-spacing: 1px; }
.management-panel { padding: 18px; }
.toolbar { display: flex; align-items: center; gap: 12px; margin-bottom: 15px; }
.toolbar input { flex: 1; }
.record-list { display: grid; gap: 10px; }
.record { display: grid; grid-template-columns: minmax(0, 1fr) minmax(230px, .8fr); gap: 18px; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding: 15px 0; }
.record h2 { margin: 0 0 6px; font-size: 15px; }
.record p, .record small, .record dt { color: var(--ns-text-718178, #718178); }
.record dl { display: grid; gap: 8px; margin: 0; font-size: 11px; }
.record dl div { display: grid; grid-template-columns: 90px 1fr; gap: 8px; }
.record dd { margin: 0; overflow-wrap: anywhere; }
.event-details-button { grid-column: 1 / -1; justify-self: end; }
.success { border: 1px solid #bbf7d0; padding: 10px 12px; color: #166534; background: #f0fdf4; font-size: 12px; }
.event-form-dialog { color: var(--ns-text-primary); }
.dialog-title { display: flex; align-items: center; justify-content: space-between; }
.event-form-fields { display: grid; gap: 14px; }
.form-field { display: grid; gap: 6px; color: var(--ns-text-secondary); font-size: 12px; }
.form-field input, .form-field textarea { width: 100%; border: 1px solid var(--ns-border); border-radius: 6px; padding: 10px 12px; background: var(--ns-surface-raised); color: var(--ns-text-primary); font: inherit; }
.form-note { margin: 0; color: var(--ns-text-secondary); font-size: 11px; line-height: 1.5; }
.event-detail-list { display: grid; gap: 10px; }
.event-detail-list div { display: grid; grid-template-columns: 100px 1fr; gap: 10px; }
.event-detail-list dt { color: var(--ns-text-secondary); }
.event-detail-list dd { margin: 0; overflow-wrap: anywhere; }
.error { color: #a34c39; }
.permission-note { margin: 16px 0 0; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding-top: 12px; color: var(--ns-text-718178, #718178); font-size: 11px; }
@media (max-width: 640px) { .record { grid-template-columns: 1fr; } .page-heading, .heading-main { align-items: flex-start; } .heading-actions { flex-wrap: wrap; justify-content: flex-end; } }
</style>
