<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
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
  department_id: string | null
  created_at: string
  updated_at: string
}

const auth = useAuthStore()
const rows = ref<EventRecord[]>([])
const loading = ref(false)
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
    .select('id,title,description,location,start_time,end_time,organizer_id,department_id,created_at,updated_at')
    .order('start_time', { ascending: true })
  loading.value = false
  if (queryError) {
    error.value = `Could not load events: ${queryError.message}`
    return
  }
  rows.value = data ?? []
}

const formatDate = (value: string) => new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
onMounted(() => { void loadEvents() })
</script>

<template>
  <main class="admin-management">
    <header class="page-heading"><div><p class="eyebrow">ADMINISTRATION</p><h1>Event Management</h1><p>Review scheduled company events and their current details.</p></div><button class="secondary-action" :disabled="loading" type="button" @click="loadEvents">{{ loading ? 'Refreshing…' : 'Refresh' }}</button></header>
    <section class="surface-card management-panel">
      <div class="toolbar"><input v-model="search" class="field-control" aria-label="Search events" placeholder="Search events"><span>{{ events.length }} events</span></div>
      <p v-if="error" class="error" role="alert">{{ error }}</p>
      <p v-else-if="loading" role="status">Loading events…</p>
      <div v-else-if="events.length" class="record-list">
        <article v-for="event in events" :key="event.id" class="record">
          <div><h2>{{ event.title }}</h2><p>{{ event.description || 'No description provided.' }}</p><small>{{ event.location || 'Location to be announced' }}</small></div>
          <dl><div><dt>Starts</dt><dd>{{ formatDate(event.start_time) }}</dd></div><div><dt>Ends</dt><dd>{{ event.end_time ? formatDate(event.end_time) : 'Not specified' }}</dd></div><div><dt>Organizer ID</dt><dd>{{ event.organizer_id }}</dd></div></dl>
        </article>
      </div>
      <p v-else>No events are currently available.</p>
      <p class="permission-note">Event changes are unavailable until database policies enforce designated-administrator access for writes.</p>
    </section>
  </main>
</template>

<style scoped>
.admin-management { color: var(--ns-text-18352d, #18352d); }
.page-heading { display: flex; justify-content: space-between; align-items: center; gap: 16px; margin-bottom: 20px; }
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
.error { color: #a34c39; }
.permission-note { margin: 16px 0 0; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding-top: 12px; color: var(--ns-text-718178, #718178); font-size: 11px; }
@media (max-width: 640px) { .record { grid-template-columns: 1fr; } .page-heading { align-items: flex-start; } }
</style>
