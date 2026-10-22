<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { type Resource, useWorkspaceStore } from '@/stores/workspace'

  const workspace = useWorkspaceStore()
  const search = ref('')
  const category = ref('All resources')
  const selected = ref<Resource | null>(null)
  const downloadError = ref('')
  const resourceLoadError = computed(() => workspace.backendError.includes('resources:'))
  const isDialogOpen = computed({
    get: () => selected.value !== null,
    set: (open: boolean) => {
      if (!open) selected.value = null
    },
  })
  const categories = computed(() => ['All resources', ...new Set(workspace.resources.map(resource => resource.category))])
  const filteredResources = computed(() => workspace.resources.filter(item => (category.value === 'All resources' || item.category === category.value) && `${item.title} ${item.description} ${item.category}`.toLowerCase().includes(search.value.trim().toLowerCase())))

  async function downloadResource (resource: Resource) {
    downloadError.value = ''
    if (!resource.fileUrl) {
      downloadError.value = 'This resource does not have a file in Northstar Storage yet.'
      return
    }
    const downloadUrl = await workspace.getResourceDownloadUrl(resource)
    if (downloadUrl) {
      window.open(downloadUrl, '_blank', 'noopener,noreferrer')
    } else {
      downloadError.value = workspace.backendError || 'The resource could not be downloaded.'
    }
  }
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">KNOWLEDGE AT YOUR FINGERTIPS</p><h1>Resources</h1><p>Policies, guides, and tools to help you do your best work.</p></div><button class="secondary-action" :disabled="workspace.loading" type="button" @click="workspace.load()">{{ workspace.loading ? 'Refreshing…' : 'Refresh' }}</button></header>
    <p v-if="downloadError" class="download-error" role="alert">{{ downloadError }}</p>
    <div class="toolbar"><input v-model="search" aria-label="Search resources" class="field-control" placeholder="Search resources"><select v-model="category" aria-label="Filter resource category" class="field-control"><option v-for="item in categories" :key="item">{{ item }}</option></select><span class="resource-count">{{ filteredResources.length }} resources</span></div>

    <p v-if="resourceLoadError" class="download-error" role="alert">Resources could not be loaded. Check the Northstar data alert above for details, then refresh.</p>
    <p v-else-if="workspace.loading && workspace.resources.length === 0" class="resource-loading" role="status">Loading resources…</p>
    <section v-else-if="filteredResources.length > 0" class="resource-grid">
      <article v-for="resource in filteredResources" :key="resource.id" class="resource-card surface-card">
        <div class="resource-top"><span class="resource-icon"><v-icon :icon="resource.format.startsWith('Course') ? 'mdi-school-outline' : 'mdi-file-document-outline'" size="21" /></span><span class="format-label">{{ resource.format.split(' · ')[0] }}</span></div>
        <span class="category-label">{{ resource.category }}</span><h2>{{ resource.title }}</h2><p>{{ resource.description }}</p><small class="updated-label">{{ resource.updatedAt }}</small>
        <div class="resource-actions"><button class="secondary-action" @click="selected = resource"><v-icon icon="mdi-eye-outline" size="16" /> View</button><button class="primary-action" @click="downloadResource(resource)"><v-icon icon="mdi-download-outline" size="16" /> Download</button></div>
      </article>
    </section>

    <div v-else class="empty-state surface-card"><v-icon icon="mdi-folder-search-outline" size="32" /><h2>{{ search || category !== 'All resources' ? 'No matching resources' : 'No resources available' }}</h2><p>{{ search || category !== 'All resources' ? 'Try a different search or category.' : 'Published company resources will appear here when available.' }}</p></div>
    <v-dialog v-model="isDialogOpen" max-width="560"><v-card v-if="selected" class="detail-dialog"><v-card-title>{{ selected.title }}</v-card-title><v-card-subtitle>{{ selected.category }} · {{ selected.format }}</v-card-subtitle><v-card-text>{{ selected.description }}<p>{{ selected.updatedAt }}</p></v-card-text><v-card-actions><v-spacer /><v-btn variant="text" @click="selected = null">Close</v-btn><v-btn color="primary" @click="downloadResource(selected)">Download</v-btn></v-card-actions></v-card></v-dialog>
  </main>
</template>

<style scoped>
.resource-count { margin-left: auto; color: var(--ns-text-829187, #829187); font-size: 10px; }
.download-error { color: var(--ns-text-a34c39, #a34c39); font-size: 10px; }
.resource-loading { padding: 14px; color: var(--ns-text-718178, #718178); }
.resource-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 13px; }
.resource-card { display: flex; min-height: 255px; flex-direction: column; padding: 17px; }
.resource-top { display: flex; align-items: center; justify-content: space-between; }
.resource-icon { display: grid; width: 40px; height: 40px; place-items: center; background: var(--ns-bg-eaf3bd, #eaf3bd); color: var(--ns-text-526738, #526738); }
.format-label { color: var(--ns-text-829187, #829187); font: 8px "DM Mono", monospace; }
.category-label { margin-top: 14px; color: var(--ns-text-71897b, #71897b); font: 8px "DM Mono", monospace; text-transform: uppercase; letter-spacing: 1px; }
.resource-card h2 { margin: 7px 0 6px; color: var(--ns-text-18352d, #18352d); font-size: 14px; }
.resource-card > p { flex: 1; margin: 0; color: var(--ns-text-718178, #718178); font-size: 10px; line-height: 1.7; }
.updated-label { margin-top: 12px; color: var(--ns-text-96a198, #96a198); font-size: 8px; }
.resource-actions { display: flex; gap: 7px; margin-top: 13px; }
.resource-actions button { flex: 1; min-height: 34px; font-size: 9px; }
.detail-dialog { padding: 10px; }
.detail-dialog .v-card-text { padding-top: 20px; line-height: 1.7; }
@media (max-width: 900px) { .resource-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (max-width: 560px) { .resource-grid { grid-template-columns: 1fr; } }
</style>
