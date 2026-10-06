<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { useWorkspaceStore } from '@/stores/workspace'

  const workspace = useWorkspaceStore()
  const showAttending = ref(false)
  const visibleEvents = computed(() => workspace.events.filter(event => !showAttending.value || event.attending))
  const dateParts = (value: string) => new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(value))
  const weekday = (value: string) => new Intl.DateTimeFormat(undefined, { weekday: 'short' }).format(new Date(value))
  const time = (value: string) => new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(value))
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">WHAT’S HAPPENING</p><h1>Events</h1><p>Make time to learn, connect, and celebrate with your colleagues.</p></div><button class="primary-action" @click="showAttending = !showAttending"><v-icon :icon="showAttending ? 'mdi-calendar-multiple-check' : 'mdi-calendar-month-outline'" size="17" />{{ showAttending ? 'All events' : 'My RSVPs' }}</button></header>

    <section class="calendar-strip surface-card">
      <div><p class="eyebrow">UP NEXT</p><strong>{{ workspace.events.length }} company events</strong></div>
      <div class="calendar-days"><div v-for="event in workspace.events.slice(0, 4)" :key="event.id"><small>{{ weekday(event.startsAt) }}</small><strong>{{ new Date(event.startsAt).getDate() }}</strong></div></div>
      <span class="calendar-month">{{ new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' }).format(new Date(workspace.events[0]?.startsAt ?? Date.now())) }}</span>
    </section>

    <section v-if="visibleEvents.length > 0" class="event-list">
      <article v-for="event in visibleEvents" :key="event.id" class="event-card surface-card">
        <div class="event-date"><small>{{ weekday(event.startsAt) }}</small><strong>{{ new Date(event.startsAt).getDate() }}</strong><span>{{ dateParts(event.startsAt).split(' ')[0] }}</span></div>
        <div class="event-info"><div class="event-kicker">{{ dateParts(event.startsAt) }} · {{ time(event.startsAt) }}</div><h2>{{ event.title }}</h2><p>{{ event.description }}</p><div class="event-details"><span><v-icon icon="mdi-map-marker-outline" size="15" />{{ event.location }}</span><span><v-icon icon="mdi-account-outline" size="15" />{{ event.organizer }}</span><span><v-icon icon="mdi-account-group-outline" size="15" />{{ event.attendees }} attending</span></div></div>
        <button class="rsvp-button" :class="{ attending: event.attending }" @click="workspace.toggleRsvp(event.id)"><v-icon :icon="event.attending ? 'mdi-check' : 'mdi-plus'" size="16" />{{ event.attending ? 'Going' : 'RSVP' }}</button>
      </article>
    </section>

    <div v-else class="empty-state surface-card"><v-icon icon="mdi-calendar-blank-outline" size="32" /><h2>No events in this list</h2><p>You have not RSVP’d to an upcoming event yet.</p></div>
  </main>
</template>

<style scoped>
.calendar-strip { display: flex; align-items: center; justify-content: space-between; gap: 18px; margin-bottom: 15px; padding: 16px 20px; }
.calendar-strip > div:first-child { display: grid; gap: 6px; }
.calendar-strip .eyebrow { margin: 0; }
.calendar-strip > div:first-child strong { color: #18352d; font-size: 12px; }
.calendar-days { display: flex; gap: 8px; }
.calendar-days > div { display: grid; min-width: 39px; gap: 4px; place-items: center; padding: 7px 5px; background: #f2f5ed; }
.calendar-days small { color: #829187; font-size: 8px; }
.calendar-days strong { color: #18352d; font-size: 13px; }
.calendar-month { color: #718178; font-size: 10px; }
.event-list { display: grid; gap: 11px; }
.event-card { display: flex; align-items: flex-start; gap: 18px; padding: 18px; }
.event-date { display: grid; flex: 0 0 48px; height: 61px; align-content: center; justify-items: center; gap: 2px; background: #eaf3bd; color: #526738; }
.event-date small, .event-date span { font: 8px "DM Mono", monospace; text-transform: uppercase; }
.event-date strong { font-size: 21px; line-height: 1; }
.event-info { flex: 1; }
.event-kicker { color: #829187; font-size: 9px; }
.event-info h2 { margin: 7px 0 5px; color: #18352d; font-size: 15px; }
.event-info > p { max-width: 730px; margin: 0; color: #718178; font-size: 10px; line-height: 1.6; }
.event-details { display: flex; flex-wrap: wrap; gap: 13px; margin-top: 11px; }
.event-details span { display: flex; align-items: center; gap: 4px; color: #75877b; font-size: 9px; }
.rsvp-button { display: flex; min-width: 75px; align-items: center; justify-content: center; gap: 5px; border: 1px solid #18352d; padding: 9px 10px; background: #18352d; color: #f5f6ee; cursor: pointer; font: 700 9px "Manrope", sans-serif; }
.rsvp-button.attending { border-color: #dce4d8; background: #f5f7f1; color: #526c5c; }
@media (max-width: 620px) { .calendar-strip { flex-wrap: wrap; } .calendar-days { order: 3; width: 100%; justify-content: space-between; } .event-card { flex-wrap: wrap; gap: 12px; } .event-info { flex-basis: calc(100% - 65px); } .rsvp-button { margin-left: 60px; } }
</style>
