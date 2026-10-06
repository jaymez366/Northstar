<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { type Resource, useWorkspaceStore } from '@/stores/workspace'

  const workspace = useWorkspaceStore()
  const search = ref('')
  const category = ref('All resources')
  const selected = ref<Resource | null>(null)
  const isDialogOpen = computed({
    get: () => selected.value !== null,
    set: (open: boolean) => {
      if (!open) selected.value = null
    },
  })
  const categories = computed(() => ['All resources', ...new Set(workspace.resources.map(resource => resource.category))])
  const filteredResources = computed(() => workspace.resources.filter(item => (category.value === 'All resources' || item.category === category.value) && `${item.title} ${item.description} ${item.category}`.toLowerCase().includes(search.value.trim().toLowerCase())))

  async function downloadResource (resource: Resource) {
    if (resource.fileUrl) {
      const downloadUrl = await workspace.getResourceDownloadUrl(resource)
      if (downloadUrl) {
        window.open(downloadUrl, '_blank', 'noopener,noreferrer')
      }
      return
    }
    const contents = `${resource.title}\n\n${resource.description}\n\nNorthstar ${resource.category} resource`
    const link = document.createElement('a')
    const objectUrl = URL.createObjectURL(new Blob([contents], { type: 'text/plain' }))
    link.href = objectUrl
    link.download = `${resource.title.toLowerCase().replaceAll(' ', '-')}.txt`
    link.click()
    URL.revokeObjectURL(objectUrl)
  }
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">KNOWLEDGE AT YOUR FINGERTIPS</p><h1>Resources</h1><p>Policies, guides, and tools to help you do your best work.</p></div></header>
    <div class="toolbar"><input v-model="search" aria-label="Search resources" class="field-control" placeholder="Search resources"><select v-model="category" aria-label="Filter resource category" class="field-control"><option v-for="item in categories" :key="item">{{ item }}</option></select><span class="resource-count">{{ filteredResources.length }} resources</span></div>

    <section v-if="filteredResources.length > 0" class="resource-grid">
      <article v-for="resource in filteredResources" :key="resource.id" class="resource-card surface-card">
        <div class="resource-top"><span class="resource-icon"><v-icon :icon="resource.format.startsWith('Course') ? 'mdi-school-outline' : 'mdi-file-document-outline'" size="21" /></span><span class="format-label">{{ resource.format.split(' · ')[0] }}</span></div>
        <span class="category-label">{{ resource.category }}</span><h2>{{ resource.title }}</h2><p>{{ resource.description }}</p><small class="updated-label">{{ resource.updatedAt }}</small>
        <div class="resource-actions"><button class="secondary-action" @click="selected = resource"><v-icon icon="mdi-eye-outline" size="16" /> View</button><button class="primary-action" @click="downloadResource(resource)"><v-icon icon="mdi-download-outline" size="16" /> Download</button></div>
      </article>
    </section>

    <div v-else class="empty-state surface-card"><v-icon icon="mdi-folder-search-outline" size="32" /><h2>No resources found</h2><p>Try a different search or category.</p></div>
    <v-dialog v-model="isDialogOpen" max-width="560"><v-card v-if="selected" class="detail-dialog"><v-card-title>{{ selected.title }}</v-card-title><v-card-subtitle>{{ selected.category }} · {{ selected.format }}</v-card-subtitle><v-card-text>{{ selected.description }}<p>{{ selected.updatedAt }}</p></v-card-text><v-card-actions><v-spacer /><v-btn variant="text" @click="selected = null">Close</v-btn><v-btn color="primary" @click="downloadResource(selected)">Download</v-btn></v-card-actions></v-card></v-dialog>
  </main>
</template>

<style scoped>
.resource-count { margin-left: auto; color: #829187; font-size: 10px; }
.resource-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 13px; }
.resource-card { display: flex; min-height: 255px; flex-direction: column; padding: 17px; }
.resource-top { display: flex; align-items: center; justify-content: space-between; }
.resource-icon { display: grid; width: 40px; height: 40px; place-items: center; background: #eaf3bd; color: #526738; }
.format-label { color: #829187; font: 8px "DM Mono", monospace; }
.category-label { margin-top: 14px; color: #71897b; font: 8px "DM Mono", monospace; text-transform: uppercase; letter-spacing: 1px; }
.resource-card h2 { margin: 7px 0 6px; color: #18352d; font-size: 14px; }
.resource-card > p { flex: 1; margin: 0; color: #718178; font-size: 10px; line-height: 1.7; }
.updated-label { margin-top: 12px; color: #96a198; font-size: 8px; }
.resource-actions { display: flex; gap: 7px; margin-top: 13px; }
.resource-actions button { flex: 1; min-height: 34px; font-size: 9px; }
.detail-dialog { padding: 10px; }
.detail-dialog .v-card-text { padding-top: 20px; line-height: 1.7; }
@media (max-width: 900px) { .resource-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (max-width: 560px) { .resource-grid { grid-template-columns: 1fr; } }
</style>
