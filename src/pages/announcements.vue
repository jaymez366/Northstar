<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue'
  import NorthstarBackButton from '@/components/NorthstarBackButton.vue'
  import { useAuthStore } from '@/stores/auth'
  import { type Announcement, useWorkspaceStore } from '@/stores/workspace'
  import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

  const auth = useAuthStore()
  const workspace = useWorkspaceStore()
  const search = ref('')
  const priority = ref('All priorities')
  const announcementLoadError = ref('')
  const adminDraft = ref({ title: '', content: '', priority: 'normal' })
  const adminCreateError = ref('')
  const adminCreateSuccess = ref('')
  const adminCreating = ref(false)
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
  const canCreateAnnouncements = computed(() => !auth.isAdmin
    && auth.profile.role === 'employee'
    && auth.canAccessEmployeeWorkspace)
  const canPinAnnouncements = computed(() => !auth.isAdmin
    && auth.profile.role === 'manager'
    && auth.canAccessEmployeeWorkspace)

  async function publishCompanyAnnouncement () {
    const title = adminDraft.value.title.trim()
    const content = adminDraft.value.content.trim()
    if (!auth.isAdmin || !auth.emailVerified || !auth.userId || !supabase || !isSupabaseConfigured || adminCreating.value) return
    if (!title || title.length > 180 || !content || content.length > 10000
        || !['normal', 'important', 'urgent'].includes(adminDraft.value.priority)) {
      adminCreateError.value = 'Enter a title and announcement text, and choose a valid priority.'
      return
    }

    adminCreating.value = true
    adminCreateError.value = ''
    adminCreateSuccess.value = ''
    const { error } = await supabase.from('announcements').insert({
      title,
      content,
      priority: adminDraft.value.priority,
      author_id: auth.userId,
      department_id: null,
    })
    adminCreating.value = false
    if (error) {
      adminCreateError.value = `Could not publish company-wide announcement: ${error.message}`
      return
    }
    adminDraft.value = { title: '', content: '', priority: 'normal' }
    adminCreateSuccess.value = 'Company-wide announcement published.'
    const refreshError = await workspace.loadAnnouncements()
    if (refreshError) announcementLoadError.value = `Could not refresh announcements: ${refreshError}`
  }

  onMounted(async () => {
    if (!auth.isAdmin) return
    const error = await workspace.loadAnnouncements()
    if (error) announcementLoadError.value = `Could not load announcements: ${error}`
  })

  function formatDate (date: string) {
    return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(date))
  }
</script>

<template>
  <main>
    <header class="page-heading">
      <NorthstarBackButton />
      <div><p class="eyebrow">COMPANY-WIDE UPDATES</p><h1>Announcements</h1><p>Company news and important updates, all in one place.</p></div>
      <router-link v-if="canCreateAnnouncements" class="primary-action" to="/employee-communication"><v-icon icon="mdi-plus" size="17" /> Create announcement</router-link>
    </header>

    <section v-if="auth.isAdmin" class="admin-create-panel surface-card" aria-labelledby="admin-announcement-heading">
      <h2 id="admin-announcement-heading">Publish an organization-wide announcement</h2>
      <p>New announcements are published for the whole organization and are not assigned to a department.</p>
      <form class="admin-create-form" @submit.prevent="publishCompanyAnnouncement">
        <label>Title<input v-model="adminDraft.title" maxlength="180" required></label>
        <label>Priority<select v-model="adminDraft.priority"><option value="normal">Normal</option><option value="important">Important</option><option value="urgent">Urgent</option></select></label>
        <label class="wide">Announcement<textarea v-model="adminDraft.content" maxlength="10000" rows="3" required /></label>
        <p v-if="adminCreateError" class="form-error" role="alert">{{ adminCreateError }}</p>
        <p v-if="adminCreateSuccess" class="form-success" role="status">{{ adminCreateSuccess }}</p>
        <button class="primary-action" :disabled="adminCreating" type="submit">{{ adminCreating ? 'Publishing…' : 'Publish announcement' }}</button>
      </form>
    </section>

    <div class="toolbar">
      <input v-model="search" aria-label="Search announcements" class="field-control" placeholder="Search announcements">

      <select v-model="priority" aria-label="Filter announcement priority" class="field-control">
        <option v-for="item in priorities" :key="item">{{ item }}</option>
      </select>

      <span class="result-count">{{ visibleAnnouncements.length }} updates</span>
    </div>

    <p v-if="announcementLoadError" class="form-error" role="alert">{{ announcementLoadError }}</p>

    <section v-if="visibleAnnouncements.length > 0" class="announcement-list">
      <article v-for="item in visibleAnnouncements" :key="item.id" class="announcement-card surface-card" :class="{ pinned: item.pinned }">
        <div class="announcement-meta">
          <span v-if="item.pinned" class="pinned-label"><v-icon icon="mdi-pin" size="14" /> PINNED</span>
          <span class="priority-label" :class="item.priority.toLowerCase()">{{ item.priority }} priority</span>
          <button v-if="canPinAnnouncements" :aria-label="item.pinned ? 'Unpin announcement' : 'Pin announcement'" class="icon-action" type="button" @click="workspace.togglePinned(item.id)"><v-icon :icon="item.pinned ? 'mdi-pin' : 'mdi-pin-outline'" size="18" /></button>
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
.admin-create-panel { display: grid; gap: 10px; margin-bottom: 18px; padding: 18px; }
.admin-create-panel h2, .admin-create-panel p { margin: 0; }
.admin-create-panel h2 { font-size: 16px; }
.admin-create-panel > p { color: var(--ns-text-829187, #829187); font-size: 11px; }
.admin-create-form { display: grid; grid-template-columns: minmax(0, 2fr) minmax(140px, 1fr); gap: 10px; }
.admin-create-form label { display: grid; gap: 5px; color: var(--ns-text-secondary, #60776b); font-size: 11px; }
.admin-create-form input, .admin-create-form select, .admin-create-form textarea { width: 100%; border: 1px solid var(--ns-border, #dce4d8); border-radius: 5px; padding: 9px; background: #fff; color: var(--ns-text-primary, #18352d); font: inherit; }
.admin-create-form .wide, .admin-create-form .form-error, .admin-create-form .form-success { grid-column: 1 / -1; }
.admin-create-form .primary-action { justify-self: start; }
@media (max-width: 640px) { .admin-create-form { grid-template-columns: 1fr; } .admin-create-form .wide, .admin-create-form .form-error, .admin-create-form .form-success { grid-column: auto; } }
.result-count { margin-left: auto; color: var(--ns-text-829187, #829187); font-size: 10px; }
.announcement-list { display: grid; gap: 12px; }
.announcement-card { padding: 20px 22px 17px; }
.announcement-card.pinned { border-left: 3px solid var(--ns-border-d4ec66, #d4ec66); }
.announcement-meta { display: flex; align-items: center; gap: 12px; }
.pinned-label, .priority-label { display: inline-flex; align-items: center; gap: 4px; color: var(--ns-text-6e8377, #6e8377); font: 9px "DM Mono", monospace; letter-spacing: .5px; }
.priority-label { margin-left: auto; padding: 5px 7px; background: var(--ns-bg-eef2e8, #eef2e8); font-family: "Manrope", sans-serif; letter-spacing: 0; }
.priority-label.high { background: var(--ns-bg-fae6de, #fae6de); color: var(--ns-text-a44c38, #a44c38); }
.priority-label.low { background: var(--ns-bg-f4f1e8, #f4f1e8); color: var(--ns-text-8c7951, #8c7951); }
.icon-action { border: 0; background: transparent; color: var(--ns-text-6e8377, #6e8377); cursor: pointer; }
.announcement-title { display: block; margin: 12px 0 6px; border: 0; padding: 0; background: transparent; color: var(--ns-text-18352d, #18352d); cursor: pointer; text-align: left; font: 700 17px "Manrope", sans-serif; }
.announcement-title:hover, .read-more:hover { color: var(--ns-text-bf593d, #bf593d); }
.announcement-card > p { max-width: 850px; margin: 0; color: var(--ns-text-718178, #718178); font-size: 11px; line-height: 1.7; }
.announcement-footer { display: flex; align-items: center; gap: 9px; margin-top: 17px; padding-top: 13px; border-top: 1px solid var(--ns-border-edf0e9, #edf0e9); }
.author-avatar { display: grid; width: 30px; height: 30px; place-items: center; border-radius: 50%; background: var(--ns-bg-eaf3bd, #eaf3bd); color: var(--ns-text-526738, #526738); font-size: 9px; font-weight: 800; }
.announcement-footer > span:nth-child(2) { display: grid; gap: 3px; }
.announcement-footer strong { color: var(--ns-text-52645a, #52645a); font-size: 10px; }
.announcement-footer small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.read-more { display: flex; align-items: center; gap: 5px; margin-left: auto; border: 0; background: transparent; color: var(--ns-text-526c5c, #526c5c); cursor: pointer; font: 600 10px "Manrope", sans-serif; }
.detail-dialog { padding: 12px; }
.detail-dialog .v-card-text { padding-top: 22px; line-height: 1.8; }
</style>
