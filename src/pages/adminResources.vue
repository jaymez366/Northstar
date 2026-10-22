<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import NorthstarBackButton from '@/components/NorthstarBackButton.vue'
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
const uploadDialog = ref(false)
const uploading = ref(false)
const uploadError = ref('')
const uploadSuccess = ref('')
const selectedFile = ref<File | null>(null)
const resourceForm = ref({ title: '', description: '', category: '' })
const error = ref('')
const search = ref('')
const maxFileSize = 50 * 1024 * 1024
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

function selectFile (event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0] ?? null
  selectedFile.value = file
  uploadError.value = file && file.size > maxFileSize
    ? 'Choose a file no larger than 50 MB.'
    : ''
}

function resetResourceForm () {
  resourceForm.value = { title: '', description: '', category: '' }
  selectedFile.value = null
  uploadError.value = ''
}

async function uploadResource () {
  if (uploading.value) return
  const file = selectedFile.value
  const title = resourceForm.value.title.trim()
  const category = resourceForm.value.category.trim()
  if (!auth.isAuthenticated || !auth.isAdmin || !auth.userId || !supabase) {
    uploadError.value = 'A signed-in Northstar administrator and Supabase connection are required.'
    return
  }
  if (!title || !category || !file) {
    uploadError.value = 'Enter a title and category, then choose a file.'
    return
  }
  if (file.size > maxFileSize) {
    uploadError.value = 'Choose a file no larger than 50 MB.'
    return
  }

  uploading.value = true
  uploadError.value = ''
  uploadSuccess.value = ''
  const safeFileName = file.name.normalize('NFKD').replace(/[^\w.-]+/g, '-').slice(-120) || 'resource-file'
  const storagePath = `resources/${crypto.randomUUID()}-${safeFileName}`
  try {
    const fileOptions = file.type ? { contentType: file.type, upsert: false } : { upsert: false }
    const { error: storageError } = await supabase.storage
      .from('company-resources')
      .upload(storagePath, file, fileOptions)
    if (storageError) throw storageError

    const { error: insertError } = await supabase.from('resources').insert({
      title,
      description: resourceForm.value.description.trim() || null,
      category,
      storage_path: storagePath,
      uploaded_by: auth.userId,
      department_id: null,
    })
    if (insertError) {
      const { error: cleanupError } = await supabase.storage.from('company-resources').remove([storagePath])
      throw new Error(cleanupError
        ? `${insertError.message}. The uploaded file could not be removed: ${cleanupError.message}`
        : insertError.message)
    }

    uploadDialog.value = false
    resetResourceForm()
    uploadSuccess.value = 'Resource uploaded.'
    await loadResources()
  } catch (uploadFailure) {
    uploadError.value = `Could not upload resource: ${uploadFailure instanceof Error ? uploadFailure.message : 'Unexpected Supabase error.'}`
  } finally {
    uploading.value = false
  }
}

const formatDate = (value: string) => new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value))
onMounted(() => { void loadResources() })
</script>

<template>
  <main class="admin-management">
    <header class="page-heading">
      <div class="heading-main"><NorthstarBackButton /><div><p class="eyebrow">ADMINISTRATION</p><h1>Resource Management</h1><p>Review company resources and download files through private signed links.</p></div></div>
      <div class="heading-actions"><button class="secondary-action" :disabled="loading" type="button" @click="loadResources">{{ loading ? 'Refreshing…' : 'Refresh' }}</button><button class="primary-action" type="button" @click="uploadDialog = true; resetResourceForm()"><v-icon icon="mdi-plus" size="17" /> Add Resource</button></div>
    </header>
    <p v-if="uploadSuccess" class="success" role="status">{{ uploadSuccess }}</p>
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
      <p class="permission-note">Resource records and private file operations remain subject to the existing table and Storage policies.</p>
    </section>
  </main>

  <v-dialog v-model="uploadDialog" max-width="600">
    <v-card class="resource-form-dialog">
      <v-card-title class="dialog-title"><span>Add resource</span><v-btn aria-label="Close resource form" icon="mdi-close" size="small" variant="text" @click="uploadDialog = false" /></v-card-title>
      <form @submit.prevent="uploadResource">
        <v-card-text class="resource-form-fields">
          <label class="form-field"><span>Resource title</span><input v-model="resourceForm.title" autocomplete="off" maxlength="180" required></label>
          <label class="form-field"><span>Description</span><textarea v-model="resourceForm.description" maxlength="10000" rows="3" /></label>
          <label class="form-field"><span>Category</span><input v-model="resourceForm.category" maxlength="100" required></label>
          <label class="form-field"><span>File</span><input type="file" required @change="selectFile"><small>{{ selectedFile ? `${selectedFile.name} · ${(selectedFile.size / 1024 / 1024).toFixed(1)} MB` : 'Maximum file size: 50 MB.' }}</small></label>
          <p class="form-note">The file stays in the private company-resources bucket. Its configured file-type rules are enforced by Storage.</p>
          <p v-if="uploadError" class="error" role="alert">{{ uploadError }}</p>
        </v-card-text>
        <v-card-actions><v-spacer /><v-btn variant="text" :disabled="uploading" @click="uploadDialog = false">Cancel</v-btn><v-btn color="primary" type="submit" :disabled="uploading" :loading="uploading">{{ uploading ? 'Uploading…' : 'Upload Resource' }}</v-btn></v-card-actions>
      </form>
    </v-card>
  </v-dialog>
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
.record { display: flex; justify-content: space-between; align-items: center; gap: 18px; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding: 15px 0; }
.record h2 { margin: 5px 0; font-size: 15px; }
.record p, .record small, .resource-actions { color: var(--ns-text-718178, #718178); font-size: 11px; }
.category { font: 9px "DM Mono", monospace; text-transform: uppercase; }
.resource-actions { display: flex; align-items: center; gap: 12px; }
.resource-form-dialog { color: var(--ns-text-primary); }
.dialog-title { display: flex; align-items: center; justify-content: space-between; }
.resource-form-fields { display: grid; gap: 14px; }
.form-field { display: grid; gap: 6px; color: var(--ns-text-secondary); font-size: 12px; }
.form-field input, .form-field textarea { width: 100%; border: 1px solid var(--ns-border); border-radius: 6px; padding: 10px 12px; background: var(--ns-surface-raised); color: var(--ns-text-primary); font: inherit; }
.form-field small, .form-note { color: var(--ns-text-secondary); font-size: 11px; line-height: 1.5; }
.form-note { margin: 0; }
.success { border: 1px solid #bbf7d0; padding: 10px 12px; color: #166534; background: #f0fdf4; font-size: 12px; }
.error { color: #a34c39; }
.permission-note { margin: 16px 0 0; border-top: 1px solid var(--ns-border-dce4d8, #dce4d8); padding-top: 12px; color: var(--ns-text-718178, #718178); font-size: 11px; }
@media (max-width: 640px) { .record, .resource-actions { align-items: flex-start; flex-direction: column; } .page-heading, .heading-main { align-items: flex-start; } .heading-actions { flex-wrap: wrap; justify-content: flex-end; } }
</style>
