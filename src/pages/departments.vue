<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { useWorkspaceStore } from '@/stores/workspace'

  const workspace = useWorkspaceStore()
  const search = ref('')
  const filteredDepartments = computed(() => workspace.departments.filter(item => `${item.name} ${item.description}`.toLowerCase().includes(search.value.trim().toLowerCase())))
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">HOW WE WORK TOGETHER</p><h1>Departments</h1><p>Meet the teams and discover what they do across Northstar.</p></div><span class="department-total">{{ workspace.departments.length }} departments</span></header>
    <div class="toolbar"><input v-model="search" aria-label="Search departments" class="field-control" placeholder="Search departments"></div>

    <section v-if="filteredDepartments.length > 0" class="department-grid">
      <article v-for="department in filteredDepartments" :key="department.name" class="department-card surface-card">
        <div class="department-heading"><span class="department-icon"><v-icon icon="mdi-domain" size="21" /></span><span class="member-count">{{ department.count }} {{ department.count === 1 ? 'member' : 'members' }}</span></div>
        <h2>{{ department.name }}</h2><p>{{ department.description }}</p>

        <div class="member-stack">
          <span v-for="member in department.members.slice(0, 4)" :key="member.id" :style="{ background: member.color }" :title="`${member.firstName} ${member.lastName}`">{{ member.initials }}</span>
          <small v-if="department.members.length > 4">+{{ department.members.length - 4 }}</small>
        </div>

        <div class="member-list">
          <router-link v-for="member in department.members" :key="member.id" :to="{ path: '/messages', query: { employee: member.id } }">
            <span class="member-avatar" :style="{ background: member.color }">{{ member.initials }}</span><span><strong>{{ member.firstName }} {{ member.lastName }}</strong><small>{{ member.title }}</small></span><v-icon icon="mdi-message-outline" size="17" />
          </router-link>
        </div>

        <router-link class="department-link" :to="{ path: '/employees', query: { department: department.name } }">View colleagues <v-icon icon="mdi-arrow-right" size="15" /></router-link>
      </article>
    </section>

    <div v-else class="empty-state surface-card"><v-icon icon="mdi-domain" size="32" /><h2>No departments found</h2><p>Try another search.</p></div>
  </main>
</template>

<style scoped>
.department-total { color: #829187; font-size: 11px; }
.department-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
.department-card { padding: 19px; }
.department-heading { display: flex; align-items: center; justify-content: space-between; }
.department-icon { display: grid; width: 41px; height: 41px; place-items: center; background: #eaf3bd; color: #526738; }
.member-count { color: #829187; font-size: 9px; }
.department-card h2 { margin: 16px 0 5px; color: #18352d; font-size: 16px; }
.department-card > p { min-height: 36px; margin: 0; color: #718178; font-size: 10px; line-height: 1.7; }
.member-stack { display: flex; align-items: center; margin: 14px 0 13px; }
.member-stack span, .member-avatar { display: grid; width: 27px; height: 27px; place-items: center; border: 2px solid #fff; border-radius: 50%; color: #18352d; font-size: 7px; font-weight: 800; }
.member-stack span + span { margin-left: -7px; }
.member-stack small { margin-left: 6px; color: #829187; font-size: 9px; }
.member-list { border-top: 1px solid #edf0e9; }
.member-list a { display: flex; align-items: center; gap: 9px; padding: 9px 0; color: #718178; text-decoration: none; }
.member-list a + a { border-top: 1px solid #f1f3ee; }
.member-avatar { flex: 0 0 28px; width: 28px; height: 28px; border: 0; }
.member-list a > span:nth-child(2) { display: grid; flex: 1; gap: 3px; }
.member-list strong { color: #52645a; font-size: 9px; }
.member-list small { color: #829187; font-size: 8px; }
.department-link { display: flex; align-items: center; gap: 5px; margin-top: 7px; color: #526c5c; text-decoration: none; font-size: 9px; font-weight: 700; }
@media (max-width: 760px) { .department-grid { grid-template-columns: 1fr; } }
</style>
