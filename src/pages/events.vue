<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { useWorkspaceStore } from '@/stores/workspace'

  const workspace = useWorkspaceStore()
  const eventPeriod = ref<'upcoming' | 'past'>('upcoming')
  const search = ref('')
  const selectedEventId = ref('')
  const selectedEvent = computed(() => workspace.events.find(event => event.id === selectedEventId.value) ?? null)
  const eventLoadError = computed(() => workspace.backendError.includes('events:'))
  const filteredEvents = computed(() => workspace.events
    .filter(event => {
      const start = new Date(event.startsAt).getTime()
      return Number.isFinite(start) && (eventPeriod.value === 'upcoming' ? start >= Date.now() : start < Date.now())
    })
    .filter(event => `${event.title} ${event.description} ${event.location} ${event.organizer}`.toLowerCase().includes(search.value.trim().toLowerCase()))
    .sort((a, b) => eventPeriod.value === 'upcoming'
      ? new Date(a.startsAt).getTime() - new Date(b.startsAt).getTime()
      : new Date(b.startsAt).getTime() - new Date(a.startsAt).getTime()))
  const dateLabel = (value: string) => {
    const date = new Date(value)
    return Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat(undefined, { dateStyle: 'full' }).format(date) : 'Date unavailable'
  }
  const timeLabel = (value: string | null | undefined) => {
    if (!value) return 'Time unavailable'
    const date = new Date(value)
    return Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(date) : 'Time unavailable'
  }
  const dateParts = (value: string) => {
    const date = new Date(value)
    return Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date) : '—'
  }
  const weekday = (value: string) => {
    const date = new Date(value)
    return Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat(undefined, { weekday: 'short' }).format(date) : '—'
  }
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">WHAT’S HAPPENING</p><h1>Events</h1><p>Make time to learn, connect, and celebrate with your colleagues.</p></div></header>

    <section class="calendar-strip surface-card">
      <div><p class="eyebrow">{{ eventPeriod === 'upcoming' ? 'UP NEXT' : 'PAST EVENTS' }}</p><strong>{{ filteredEvents.length }} {{ eventPeriod }} events</strong></div>
      <div class="calendar-days"><div v-for="event in filteredEvents.slice(0, 4)" :key="event.id"><small>{{ weekday(event.startsAt) }}</small><strong>{{ dateParts(event.startsAt).split(' ')[1] ?? '—' }}</strong></div></div>
      <nav aria-label="Event time filter" class="event-period-tabs">
        <button :aria-pressed="eventPeriod === 'upcoming'" type="button" @click="eventPeriod = 'upcoming'">Upcoming</button>
        <button :aria-pressed="eventPeriod === 'past'" type="button" @click="eventPeriod = 'past'">Past</button>
      </nav>
    </section>

    <div class="events-toolbar">
      <input v-model="search" aria-label="Search events" class="field-control" placeholder="Search event title or details">
      <button class="secondary-action" :disabled="workspace.loading" type="button" @click="workspace.load()">{{ workspace.loading ? 'Refreshing…' : 'Refresh' }}</button>
    </div>

    <p v-if="eventLoadError" class="events-message" role="alert">Events could not be loaded. Check the Northstar data alert above for details, then refresh.</p>
    <p v-else-if="workspace.loading && workspace.events.length === 0" class="events-message" role="status">Loading events…</p>
    <section v-else-if="filteredEvents.length > 0" class="event-list">
      <article v-for="event in filteredEvents" :key="event.id" class="event-card surface-card">
        <div class="event-date"><small>{{ weekday(event.startsAt) }}</small><strong>{{ new Date(event.startsAt).getDate() }}</strong><span>{{ dateParts(event.startsAt).split(' ')[0] }}</span></div>
        <div class="event-info"><div class="event-kicker">{{ dateLabel(event.startsAt) }} · {{ timeLabel(event.startsAt) }}</div><h2>{{ event.title }}</h2><p>{{ event.description }}</p><div class="event-details"><span><v-icon icon="mdi-map-marker-outline" size="15" />{{ event.location || 'Location to be announced' }}</span><span><v-icon icon="mdi-account-outline" size="15" />{{ event.organizer }}</span><span><v-icon icon="mdi-account-group-outline" size="15" />{{ event.attendees }} attending</span></div></div>
        <div class="event-actions">
          <button class="secondary-action" type="button" @click="selectedEventId = event.id">Details</button>
          <button v-if="eventPeriod === 'upcoming'" class="rsvp-button" :class="{ attending: event.attending }" type="button" @click="workspace.toggleRsvp(event.id)"><v-icon :icon="event.attending ? 'mdi-check' : 'mdi-plus'" size="16" />{{ event.attending ? 'Going' : 'RSVP' }}</button>
        </div>
      </article>
    </section>

    <div v-else class="empty-state surface-card"><v-icon icon="mdi-calendar-blank-outline" size="32" /><h2>{{ search ? 'No matching events' : `No ${eventPeriod} events` }}</h2><p>{{ search ? 'Try another search.' : 'Company events will appear here when available.' }}</p></div>
    <v-dialog :model-value="selectedEvent !== null" max-width="560" @update:model-value="!$event && (selectedEventId = '')">
      <v-card v-if="selectedEvent" class="event-detail-dialog">
        <v-card-title>{{ selectedEvent.title }}</v-card-title>
        <v-card-subtitle>{{ dateLabel(selectedEvent.startsAt) }} · {{ timeLabel(selectedEvent.startsAt) }}<span v-if="selectedEvent.endsAt">–{{ timeLabel(selectedEvent.endsAt) }}</span></v-card-subtitle>
        <v-card-text><p>{{ selectedEvent.description || 'No additional details are available.' }}</p><dl><div><dt>Location</dt><dd>{{ selectedEvent.location || 'Location to be announced' }}</dd></div><div><dt>Organiser</dt><dd>{{ selectedEvent.organizer }}</dd></div><div><dt>Attendance</dt><dd>{{ selectedEvent.attendees }} attending</dd></div></dl></v-card-text>
        <v-card-actions><v-spacer /><v-btn variant="text" @click="selectedEventId = ''">Close</v-btn><v-btn v-if="eventPeriod === 'upcoming'" color="primary" @click="workspace.toggleRsvp(selectedEvent.id)">{{ selectedEvent.attending ? 'Cancel RSVP' : 'RSVP' }}</v-btn></v-card-actions>
      </v-card>
    </v-dialog>
  </main>
</template>

<style scoped>
.calendar-strip { display: flex; align-items: center; justify-content: space-between; gap: 18px; margin-bottom: 15px; padding: 16px 20px; }
.calendar-strip > div:first-child { display: grid; gap: 6px; }
.calendar-strip .eyebrow { margin: 0; }
.calendar-strip > div:first-child strong { color: var(--ns-text-18352d, #18352d); font-size: 12px; }
.calendar-days { display: flex; gap: 8px; }
.calendar-days > div { display: grid; min-width: 39px; gap: 4px; place-items: center; padding: 7px 5px; background: var(--ns-bg-f2f5ed, #f2f5ed); }
.calendar-days small { color: var(--ns-text-829187, #829187); font-size: 8px; }
.calendar-days strong { color: var(--ns-text-18352d, #18352d); font-size: 13px; }
.event-period-tabs { display: flex; gap: 5px; padding: 4px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); border-radius: 8px; }
.event-period-tabs button { border: 0; border-radius: 5px; padding: 8px 11px; background: transparent; color: var(--ns-text-718178, #718178); cursor: pointer; font: 600 10px "Manrope", sans-serif; }
.event-period-tabs button[aria-pressed="true"] { background: var(--ns-bg-18352d, #18352d); color: var(--ns-text-f5f6ee, #f5f6ee); }
.events-toolbar { display: flex; gap: 9px; margin-bottom: 14px; }
.events-toolbar input { min-width: 0; flex: 1; }
.events-message { padding: 14px; color: var(--ns-text-718178, #718178); }
.event-list { display: grid; gap: 11px; }
.event-card { display: flex; align-items: flex-start; gap: 18px; padding: 18px; }
.event-date { display: grid; flex: 0 0 48px; height: 61px; align-content: center; justify-items: center; gap: 2px; background: var(--ns-bg-eaf3bd, #eaf3bd); color: var(--ns-text-526738, #526738); }
.event-date small, .event-date span { font: 8px "DM Mono", monospace; text-transform: uppercase; }
.event-date strong { font-size: 21px; line-height: 1; }
.event-info { flex: 1; }
.event-kicker { color: var(--ns-text-829187, #829187); font-size: 9px; }
.event-info h2 { margin: 7px 0 5px; color: var(--ns-text-18352d, #18352d); font-size: 15px; }
.event-info > p { max-width: 730px; margin: 0; color: var(--ns-text-718178, #718178); font-size: 10px; line-height: 1.6; }
.event-details { display: flex; flex-wrap: wrap; gap: 13px; margin-top: 11px; }
.event-details span { display: flex; align-items: center; gap: 4px; color: var(--ns-text-75877b, #75877b); font-size: 9px; }
.event-actions { display: flex; flex-wrap: wrap; gap: 7px; }
.rsvp-button { display: flex; min-width: 75px; align-items: center; justify-content: center; gap: 5px; border: 1px solid var(--ns-border-18352d, #18352d); padding: 9px 10px; background: var(--ns-bg-18352d, #18352d); color: var(--ns-text-f5f6ee, #f5f6ee); cursor: pointer; font: 700 9px "Manrope", sans-serif; }
.rsvp-button.attending { border-color: var(--ns-border-dce4d8, #dce4d8); background: var(--ns-bg-f5f7f1, #f5f7f1); color: var(--ns-text-526c5c, #526c5c); }
.event-detail-dialog { padding: 8px; }
.event-detail-dialog dl { display: grid; gap: 10px; }
.event-detail-dialog dl div { display: grid; grid-template-columns: 100px 1fr; gap: 10px; }
.event-detail-dialog dt { color: var(--ns-text-718178, #718178); }
.event-detail-dialog dd { margin: 0; color: var(--ns-text-18352d, #18352d); }
@media (max-width: 620px) { .calendar-strip { flex-wrap: wrap; } .calendar-days { order: 3; width: 100%; justify-content: space-between; } .event-card { flex-wrap: wrap; gap: 12px; } .event-info { flex-basis: calc(100% - 65px); } .event-actions { width: 100%; margin-left: 60px; } }
</style>
