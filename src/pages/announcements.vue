<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { type Announcement, useWorkspaceStore } from '@/stores/workspace'

  const workspace = useWorkspaceStore()
  const search = ref('')
  const priority = ref('All priorities')
  const selected = ref<Announcement | null>(null)
  const isDialogOpen = computed({
    get: () => selected.value !== null,
    set: (open: boolean) => {
      if (!open) selected.value = null
    },
  })
  const visibleAnnouncements = computed(() => {
    const filtered = workspace.announcements.filter(item =>
      (priority.value === 'All priorities' || item.priority === priority.value)
      && `${item.title} ${item.description} ${item.author} ${item.department}`.toLowerCase().includes(search.value.trim().toLowerCase()))

    return [
      ...filtered.filter(item => item.pinned),
      ...filtered.filter(item => !item.pinned),
    ]
  })
  const priorities = ['All priorities', 'High', 'Normal', 'Low']

  function formatDate (date: string) {
    return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(date))
  }
</script>

<template>
  <main>
    <header class="page-heading">
      <div><p class="eyebrow">COMPANY-WIDE UPDATES</p><h1>Announcements</h1><p>Company news and important updates, all in one place.</p></div>
      <router-link class="primary-action" to="/employee-communication"><v-icon icon="mdi-plus" size="17" /> Create announcement</router-link>
    </header>

    <div class="toolbar">
      <input v-model="search" aria-label="Search announcements" class="field-control" placeholder="Search announcements">

      <select v-model="priority" aria-label="Filter announcement priority" class="field-control">
        <option v-for="item in priorities" :key="item">{{ item }}</option>
      </select>

      <span class="result-count">{{ visibleAnnouncements.length }} updates</span>
    </div>

    <section v-if="visibleAnnouncements.length > 0" class="announcement-list">
      <article v-for="item in visibleAnnouncements" :key="item.id" class="announcement-card surface-card" :class="{ pinned: item.pinned }">
        <div class="announcement-meta">
          <span v-if="item.pinned" class="pinned-label"><v-icon icon="mdi-pin" size="14" /> PINNED</span>
          <span class="priority-label" :class="item.priority.toLowerCase()">{{ item.priority }} priority</span>
          <button :aria-label="item.pinned ? 'Unpin announcement' : 'Pin announcement'" class="icon-action" @click="workspace.togglePinned(item.id)"><v-icon :icon="item.pinned ? 'mdi-pin' : 'mdi-pin-outline'" size="18" /></button>
        </div>

        <button class="announcement-title" @click="selected = item">{{ item.title }}</button>
        <p>{{ item.description }}</p>

        <div class="announcement-footer">
          <span class="author-avatar">{{ item.author.split(' ').map(name => name[0]).join('') }}</span>
          <span><strong>{{ item.author }}</strong><small>{{ item.department }} · {{ formatDate(item.createdAt) }}</small></span>
          <button class="read-more" @click="selected = item">Read update <v-icon icon="mdi-arrow-right" size="15" /></button>
        </div>
      </article>
    </section>

    <div v-else class="empty-state surface-card"><v-icon icon="mdi-bullhorn-outline" size="32" /><h2>No announcements found</h2><p>Try changing your search or filters.</p></div>

    <v-dialog v-model="isDialogOpen" max-width="620">
      <v-card v-if="selected" class="detail-dialog">
        <v-card-title>{{ selected.title }}</v-card-title>
        <v-card-subtitle>{{ selected.author }} · {{ formatDate(selected.createdAt) }}</v-card-subtitle>
        <v-card-text>{{ selected.description }}</v-card-text>
        <v-card-actions><v-spacer /><v-btn color="primary" variant="text" @click="selected = null">Close</v-btn></v-card-actions>
      </v-card>
    </v-dialog>
  </main>
</template>

<style scoped>
.result-count { margin-left: auto; color: #829187; font-size: 10px; }
.announcement-list { display: grid; gap: 12px; }
.announcement-card { padding: 20px 22px 17px; }
.announcement-card.pinned { border-left: 3px solid #d4ec66; }
.announcement-meta { display: flex; align-items: center; gap: 12px; }
.pinned-label, .priority-label { display: inline-flex; align-items: center; gap: 4px; color: #6e8377; font: 9px "DM Mono", monospace; letter-spacing: .5px; }
.priority-label { margin-left: auto; padding: 5px 7px; background: #eef2e8; font-family: "Manrope", sans-serif; letter-spacing: 0; }
.priority-label.high { background: #fae6de; color: #a44c38; }
.priority-label.low { background: #f4f1e8; color: #8c7951; }
.icon-action { border: 0; background: transparent; color: #6e8377; cursor: pointer; }
.announcement-title { display: block; margin: 12px 0 6px; border: 0; padding: 0; background: transparent; color: #18352d; cursor: pointer; text-align: left; font: 700 17px "Manrope", sans-serif; }
.announcement-title:hover, .read-more:hover { color: #bf593d; }
.announcement-card > p { max-width: 850px; margin: 0; color: #718178; font-size: 11px; line-height: 1.7; }
.announcement-footer { display: flex; align-items: center; gap: 9px; margin-top: 17px; padding-top: 13px; border-top: 1px solid #edf0e9; }
.author-avatar { display: grid; width: 30px; height: 30px; place-items: center; border-radius: 50%; background: #eaf3bd; color: #526738; font-size: 9px; font-weight: 800; }
.announcement-footer > span:nth-child(2) { display: grid; gap: 3px; }
.announcement-footer strong { color: #52645a; font-size: 10px; }
.announcement-footer small { color: #829187; font-size: 9px; }
.read-more { display: flex; align-items: center; gap: 5px; margin-left: auto; border: 0; background: transparent; color: #526c5c; cursor: pointer; font: 600 10px "Manrope", sans-serif; }
.detail-dialog { padding: 12px; }
.detail-dialog .v-card-text { padding-top: 22px; line-height: 1.8; }
</style>
