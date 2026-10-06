<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { useRoute } from 'vue-router'
  import { useWorkspaceStore } from '@/stores/workspace'

  const workspace = useWorkspaceStore()
  const route = useRoute()
  const search = ref('')
  const department = ref(typeof route.query.department === 'string' ? route.query.department : 'All departments')
  const departments = computed(() => ['All departments', ...new Set(workspace.employees.map(employee => employee.department))])
  const filteredEmployees = computed(() => workspace.employees.filter(employee => {
    const text = `${employee.firstName} ${employee.lastName} ${employee.title} ${employee.department} ${employee.email}`.toLowerCase()
    return (department.value === 'All departments' || employee.department === department.value)
      && text.includes(search.value.trim().toLowerCase())
  }))
</script>

<template>
  <main>
    <header class="page-heading">
      <div><p class="eyebrow">YOUR PEOPLE</p><h1>Employee directory</h1><p>Find the right person, team, or expertise across Northstar.</p></div>
      <span class="directory-count">{{ filteredEmployees.length }} colleagues</span>
    </header>

    <div class="toolbar">
      <input v-model="search" aria-label="Search employees" class="field-control" placeholder="Search name, role, or email">

      <select v-model="department" aria-label="Filter by department" class="field-control">
        <option v-for="item in departments" :key="item">{{ item }}</option>
      </select>
    </div>

    <section v-if="filteredEmployees.length > 0" aria-label="Employees" class="employee-grid">
      <article v-for="employee in filteredEmployees" :key="employee.id" class="employee-card surface-card">
        <div class="employee-card-top">
          <span class="employee-avatar" :style="employee.photoUrl ? { backgroundImage: `url(${employee.photoUrl})` } : { background: employee.color }">{{ employee.photoUrl ? '' : employee.initials }}</span>
          <span class="presence" :class="{ online: employee.online }"><i />{{ employee.online ? 'Online' : 'Offline' }}</span>
        </div>

        <h2>{{ employee.firstName }} {{ employee.lastName }}</h2>
        <p class="employee-title">{{ employee.title }}</p>
        <span class="department-chip">{{ employee.department }}</span>
        <a class="employee-email" :href="`mailto:${employee.email}`">{{ employee.email }}</a>

        <div class="employee-actions">
          <router-link class="secondary-action" :to="{ path: '/messages', query: { employee: employee.id } }"><v-icon icon="mdi-message-outline" size="17" /> Message</router-link>
          <a :aria-label="`Email ${employee.firstName}`" class="contact-action" :href="`mailto:${employee.email}`"><v-icon icon="mdi-email-outline" size="18" /></a>
        </div>
      </article>
    </section>

    <div v-else class="empty-state surface-card"><v-icon icon="mdi-account-search-outline" size="32" /><h2>No colleagues found</h2><p>Try a different name or department.</p></div>
  </main>
</template>

<style scoped>
.directory-count { color: #829187; font-size: 11px; }
.employee-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; }
.employee-card { padding: 19px; }
.employee-card-top { display: flex; align-items: center; justify-content: space-between; }
.employee-avatar { display: grid; width: 48px; height: 48px; place-items: center; border-radius: 50%; color: #18352d; font-size: 13px; font-weight: 800; }
.employee-avatar[style*="background-image"] { background-position: center; background-size: cover; }
.presence { display: flex; align-items: center; gap: 5px; color: #829187; font-size: 9px; }
.presence i { width: 6px; height: 6px; border-radius: 50%; background: #a5b0a8; }
.presence.online i { background: #70a879; }
.employee-card h2 { margin: 17px 0 4px; color: #18352d; font-size: 15px; }
.employee-title { margin: 0; color: #718178; font-size: 10px; }
.department-chip { display: inline-block; margin-top: 12px; padding: 5px 8px; background: #edf2e6; color: #526c5c; font-size: 9px; }
.employee-email { display: block; overflow: hidden; margin-top: 14px; color: #627d6d; text-overflow: ellipsis; font-size: 10px; text-decoration: none; white-space: nowrap; }
.employee-actions { display: flex; gap: 8px; margin-top: 16px; }
.employee-actions .secondary-action { flex: 1; }
.contact-action { display: grid; width: 40px; place-items: center; border: 1px solid #d1dbcd; color: #526c5c; }
@media (max-width: 900px) { .employee-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (max-width: 520px) { .employee-grid { grid-template-columns: 1fr; } }
</style>
