<template>
  <v-app>
    <v-main>
      <AdminLayout v-if="route.meta.requiresAdmin">
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

  const route = useRoute()
</script>
