<template>
  <v-app>
    <v-main>
      <WorkspaceLayout v-if="route.meta.requiresAuth">
        <router-view />
      </WorkspaceLayout>

      <router-view v-else />
    </v-main>
  </v-app>
</template>

<script lang="ts" setup>
  import { useRoute } from 'vue-router'
  import WorkspaceLayout from '@/components/WorkspaceLayout.vue'

  const route = useRoute()
</script>
