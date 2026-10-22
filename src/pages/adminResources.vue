<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

type ResourceRecord = {
  id: string
  title: string
  description: string | null
  category: string
  storage_path: string
  uploaded_by: string
  department_id: string | null
  created_at: string
  updated_at: string
}

const auth = useAuthStore()
const rows = ref<ResourceRecord[]>([])
const uploaderNames = ref<Record<string, string>>({})
const loading = ref(false)
const downloadingId = ref('')
const error = ref('')
const search = ref('')
const resources = computed(() => rows.value.filter(resource =>
  `${resource.title} ${resource.description ?? ''} ${resource.category}`.toLowerCase().includes(search.value.trim().toLowerCase())))

async function loadResources () {
  if (!auth.isAuthenticated || !auth.isAdmin) return
  if (!isSupabaseConfigured || !supabase) {
    error.value = 'Northstar Supabase is not configured.'
    return
  }
  loading.value = true
  error.value = ''
  const { data, error: queryError } = await supabase.from('resources')
    .select('id,title,description,category,storage_path,uploaded_by,department_id,created_at,updated_at')
    .order('updated_at', { ascending: false })
  loading.value = false
  if (queryError) {
    error.value = `Could not load resources: ${queryError.message}`
    return
  }
  rows.value = data ?? []
  const uploaderIds = [...new Set(rows.value.map(resource => resource.uploaded_by).filter(Boolean))]
  uploaderNames.value = {}
  if (uploaderIds.length) {
    const { data: profiles } = await supabase.from('profiles').select('id,first_name,last_name').in('id', uploaderIds)
    uploaderNames.value = Object.fromEntries((profiles ?? []).map(profile => [
      profile.id,
      `${profile.first_name ?? ''} ${profile.last_name ?? ''}`.trim(),
    ]))
  }
}

async function download (resource: ResourceRecord) {
  if (!auth.isAuthenticated || !auth.isAdmin || !supabase || !resource.storage_path) return
  downloadingId.value = resource.id
  error.value = ''
  const { data, error: downloadError } = await supabase.storage.from('company-resources').createSignedUrl(resource.storage_path, 60)
  downloadingId.value = ''
  if (downloadError) {
    error.value = `Could not create a private download link: ${downloadError.message}`
    return
  }
  window.location.assign(data.signedUrl)
}

const formatDate = (value: string) => new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value))
onMounted(() => { void loadResources() })
</script>

<template>
  <main class="admin-management">
    <header class="page-heading"><div><p class="eyebrow">ADMINISTRATION</p><h1>Resource Management</h1><p>Review company resources and download files through private signed links.</p></div><button class="secondary-action" :disabled="loading" type="button" @click="loadResources">{{ loading ? 'Refreshing…' : 'Refresh' }}</button></header>
    <section class="surface-card management-panel">
      <div class="toolbar"><input v-model="search" class="field-control" aria-label="Search resources" placeholder="Search resources"><span>{{ resources.length }} resources</span></div>
      <p v-if="error" class="error" role="alert">{{ error }}</p>
      <p v-else-if="loading" role="status">Loading resources…</p>
      <div v-else-if="resources.length" class="record-list">
        <article v-for="resource in resources" :key="resource.id" class="record">
          <div><span class="category">{{ resource.category }}</span><h2>{{ resource.title }}</h2><p>{{ resource.description || 'No description provided.' }}</p><small>Updated {{ formatDate(resource.updated_at || resource.created_at) }}</small></div>
          <div class="resource-actions"><span>Uploaded by {{ uploaderNames[resource.uploaded_by] || 'Name unavailable' }}</span><button class="secondary-action" type="button" :disabled="downloadingId === resource.id" @click="download(resource)">{{ downloadingId === resource.id ? 'Preparing…' : 'Download' }}</button></div>
        </article>
      </div>
      <p v-else>No resources are currently available.</p>
      <p class="permission-note">Resource changes are unavailable until database and Storage policies enforce designated-administrator access for writes.</p>
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
.record { display: flex; justify-content: space-between; align-items: center; gap: 18px; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding: 15px 0; }
.record h2 { margin: 5px 0; font-size: 15px; }
.record p, .record small, .resource-actions { color: var(--ns-text-718178, #718178); font-size: 11px; }
.category { font: 9px "DM Mono", monospace; text-transform: uppercase; }
.resource-actions { display: flex; align-items: center; gap: 12px; }
.error { color: #a34c39; }
.permission-note { margin: 16px 0 0; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding-top: 12px; color: var(--ns-text-718178, #718178); font-size: 11px; }
@media (max-width: 640px) { .record, .resource-actions { align-items: flex-start; flex-direction: column; } .page-heading { align-items: flex-start; } }
</style>
