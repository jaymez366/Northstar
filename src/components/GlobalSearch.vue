<script setup lang="ts">
  import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useWorkspaceStore } from '@/stores/workspace'

  const router = useRouter()
  const route = useRoute()
  const workspace = useWorkspaceStore()
  const query = ref('')
  const isFocused = ref(false)
  const searchInput = ref<HTMLInputElement | null>(null)
  const searchRoot = ref<HTMLDivElement | null>(null)

  const results = computed(() => {
    const term = query.value.trim().toLowerCase()
    if (term.length < 2) return []

    return [
      ...workspace.employees.map(employee => ({
        id: `employee-${employee.id}`,
        title: `${employee.firstName} ${employee.lastName}`,
        detail: `${employee.title} · ${employee.department}`,
        icon: 'mdi-account-outline',
        to: '/employees',
      })),
      ...workspace.announcements.map(item => ({
        id: `announcement-${item.id}`,
        title: item.title,
        detail: `Announcement · ${item.author}`,
        icon: 'mdi-bullhorn-outline',
        to: '/announcements',
      })),
      ...workspace.conversations.map(item => ({
        id: `message-${item.id}`,
        title: item.name,
        detail: `Message · ${item.messages.at(-1)?.text ?? 'Conversation'}`,
        icon: 'mdi-message-outline',
        to: '/messages',
      })),
      ...workspace.departments.map(item => ({
        id: `department-${item.name}`,
        title: item.name,
        detail: `Department · ${item.count} employees`,
        icon: 'mdi-domain',
        to: '/departments',
      })),
      ...workspace.events.map(item => ({
        id: `event-${item.id}`,
        title: item.title,
        detail: `Event · ${item.location}`,
        icon: 'mdi-calendar-outline',
        to: '/events',
      })),
      ...workspace.resources.map(item => ({
        id: `resource-${item.id}`,
        title: item.title,
        detail: `Resource · ${item.category}`,
        icon: 'mdi-file-document-outline',
        to: '/resources',
      })),
    ].filter(item => `${item.title} ${item.detail}`.toLowerCase().includes(term)).slice(0, 7)
  })

  function openResult (to: string) {
    query.value = ''
    isFocused.value = false
    router.push(to)
  }

  function handleShortcut (event: KeyboardEvent) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault()
      searchInput.value?.focus()
    }
  }

  function handleOutsideClick (event: PointerEvent) {
    if (!searchRoot.value?.contains(event.target as Node)) isFocused.value = false
  }

  watch(() => route.fullPath, () => {
    query.value = ''
    isFocused.value = false
    searchInput.value?.blur()
  })

  onMounted(() => window.addEventListener('keydown', handleShortcut))
  onMounted(() => window.addEventListener('pointerdown', handleOutsideClick))
  onUnmounted(() => {
    window.removeEventListener('keydown', handleShortcut)
    window.removeEventListener('pointerdown', handleOutsideClick)
  })
</script>

<template>
  <div ref="searchRoot" class="global-search" @keydown.esc="isFocused = false">
    <v-icon icon="mdi-magnify" size="19" />

    <input
      ref="searchInput"
      v-model="query"
      aria-label="Search employees, announcements, messages, departments, events, and resources"
      autocomplete="off"
      placeholder="Search everything..."
      type="search"
      @focus="isFocused = true"
    >

    <kbd>Ctrl K</kbd>

    <div v-if="isFocused && query.trim().length >= 2" class="search-results">
      <button
        v-for="result in results"
        :key="result.id"
        type="button"
        @click="openResult(result.to)"
      >
        <v-icon :icon="result.icon" size="19" />
        <span><strong>{{ result.title }}</strong><small>{{ result.detail }}</small></span>
        <v-icon class="result-arrow" icon="mdi-arrow-top-left" size="15" />
      </button>

      <p v-if="results.length === 0">No results found for “{{ query }}”.</p>
    </div>
  </div>
</template>

<style scoped>
.global-search {
  position: relative;
  display: flex;
  align-items: center;
  gap: 10px;
  width: min(420px, 48vw);
  height: 42px;
  padding: 0 13px;
  border: 1px solid #dce4d8;
  background: #fff;
  color: #718178;
}
input {
  width: 100%;
  border: 0;
  outline: none;
  color: #18352d;
  background: transparent;
  font: 12px "Manrope", sans-serif;
}
kbd {
  flex: none;
  padding: 3px 5px;
  border: 1px solid #dce4d8;
  color: #829187;
  font: 9px "DM Mono", monospace;
}
.search-results {
  position: absolute;
  z-index: 20;
  top: calc(100% + 6px);
  right: 0;
  left: 0;
  padding: 6px;
  border: 1px solid #dce4d8;
  background: #fff;
  box-shadow: 0 14px 32px #102d261c;
}
.search-results button {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 11px;
  border: 0;
  padding: 10px;
  background: transparent;
  color: #526c5c;
  cursor: pointer;
  text-align: left;
}
.search-results button:hover { background: #f3f5ef; }
.search-results button span { display: grid; flex: 1; gap: 4px; }
.search-results strong { color: #18352d; font-size: 11px; }
.search-results small { color: #829187; font-size: 10px; }
.search-results .result-arrow { opacity: .5; }
.search-results p { margin: 8px; color: #829187; font-size: 11px; }
@media (max-width: 600px) {
  .global-search { width: 100%; }
  kbd { display: none; }
}
</style>
