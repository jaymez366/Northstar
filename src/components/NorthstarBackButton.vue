<script setup lang="ts">
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const auth = useAuthStore()

async function goBack () {
  const previousPath = router.options.history.state.back

  if (typeof previousPath === 'string' && previousPath.startsWith('/') && !previousPath.startsWith('//')) {
    const previousRoute = router.resolve(previousPath)
    const blockedPaths = ['/login', '/admin-login', '/verify-email', '/auth/callback']
    const isBlockedPath = blockedPaths.some(path => previousRoute.path === path || previousRoute.path.startsWith(`${path}/`))
    const isAccessible = auth.isAdmin
      ? !previousRoute.meta.requiresEmployeeWorkspace || Boolean(previousRoute.meta.allowDesignatedAdmin)
      : !previousRoute.meta.requiresAdmin

    if (previousRoute.matched.length > 0 && !isBlockedPath && isAccessible && previousRoute.fullPath !== router.currentRoute.value.fullPath) {
      await router.push(previousRoute.fullPath)
      return
    }
  }

  await router.push(auth.isAdmin ? '/admin' : '/overview')
}
</script>

<template>
  <v-tooltip text="Go back">
    <template #activator="{ props }">
      <v-btn
        v-bind="props"
        aria-label="Go back"
        class="northstar-back-button"
        density="comfortable"
        icon="mdi-arrow-left"
        size="small"
        variant="text"
        @click="goBack"
      />
    </template>
  </v-tooltip>
</template>

<style scoped>
.northstar-back-button { flex: 0 0 auto; color: var(--ns-text-primary); }
.northstar-back-button:focus-visible { outline: 2px solid var(--ns-primary); outline-offset: 2px; }
</style>
