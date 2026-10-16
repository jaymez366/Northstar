<template>
  <v-app>
    <v-main>
      <AdminLayout v-if="route.meta.requiresAdmin || (route.meta.adminReadable && auth.isAdmin)">
        <router-view />
      </AdminLayout>

      <WorkspaceLayout v-else-if="route.meta.requiresAuth">
        <router-view />
      </WorkspaceLayout>

      <router-view v-else />
    </v-main>
  </v-app>
</template>

<script lang="ts" setup>
  import { useRoute } from 'vue-router'
  import AdminLayout from '@/components/AdminLayout.vue'
  import WorkspaceLayout from '@/components/WorkspaceLayout.vue'
  import { useAuthStore } from '@/stores/auth'

  const route = useRoute()
  const auth = useAuthStore()
</script>
