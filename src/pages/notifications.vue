<script setup lang="ts">
  import { computed, ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { useWorkspaceStore } from '@/stores/workspace'

  const workspace = useWorkspaceStore()
  const router = useRouter()
  const category = ref('All activity')
  const categories = ['All activity', 'Announcements', 'Messages', 'Events', 'People']
  const filteredNotifications = computed(() => workspace.notifications.filter(item => category.value === 'All activity' || item.category === category.value))
  const iconFor = (type: string) => ({ Announcements: 'mdi-bullhorn-outline', Messages: 'mdi-message-outline', Events: 'mdi-calendar-outline', People: 'mdi-account-outline' })[type] ?? 'mdi-bell-outline'

  function openNotification (id: string, to: string) {
    workspace.markNotificationRead(id)
    router.push(to)
  }
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">YOUR ACTIVITY</p><h1>Notifications</h1><p>Important updates from across your Northstar workspace.</p></div><button class="secondary-action" :disabled="!workspace.unreadNotifications" @click="workspace.markAllNotificationsRead">Mark all as read</button></header>

    <div class="toolbar">
      <select v-model="category" aria-label="Filter notifications by category" class="field-control"><option v-for="item in categories" :key="item">{{ item }}</option></select>
      <span class="notification-summary">{{ workspace.unreadNotifications }} unread</span>
    </div>

    <section v-if="filteredNotifications.length > 0" aria-label="Notification list" class="notification-list surface-card">
      <article v-for="item in filteredNotifications" :key="item.id" class="notification-item" :class="{ unread: item.unread }">
        <button class="notification-open" @click="openNotification(item.id, item.to)">
          <span class="notification-icon"><v-icon :icon="iconFor(item.category)" size="19" /></span>
          <span class="notification-content"><strong>{{ item.title }}</strong><span>{{ item.description }}</span><small>{{ item.category }} · {{ item.createdAt }}</small></span>
          <i v-if="item.unread" class="unread-dot" />
        </button>

        <button :aria-label="`Clear ${item.title}`" class="delete-notification" @click="workspace.deleteNotification(item.id)"><v-icon icon="mdi-close" size="17" /></button>
      </article>
    </section>

    <div v-else class="empty-state surface-card"><v-icon icon="mdi-bell-check-outline" size="32" /><h2>You’re all caught up</h2><p>There are no notifications in this category.</p></div>
  </main>
</template>

<style scoped>
.notification-summary { margin-left: auto; color: var(--ns-text-829187, #829187); font-size: 10px; }
.notification-list { overflow: hidden; }
.notification-item { display: flex; align-items: center; border-bottom: 1px solid var(--ns-border-edf0e9, #edf0e9); }
.notification-item:last-child { border-bottom: 0; }
.notification-item.unread { background: var(--ns-bg-fcfdf9, #fcfdf9); }
.notification-open { display: flex; min-width: 0; flex: 1; align-items: center; gap: 13px; border: 0; padding: 17px 16px; background: transparent; cursor: pointer; text-align: left; }
.notification-icon { display: grid; flex: 0 0 38px; width: 38px; height: 38px; place-items: center; background: var(--ns-bg-eef2e8, #eef2e8); color: var(--ns-text-617a68, #617a68); }
.notification-content { display: grid; min-width: 0; flex: 1; gap: 5px; }
.notification-content strong { color: var(--ns-text-18352d, #18352d); font-size: 11px; }
.notification-content > span { overflow: hidden; color: var(--ns-text-718178, #718178); text-overflow: ellipsis; font-size: 10px; white-space: nowrap; }
.notification-content small { color: var(--ns-text-94a097, #94a097); font-size: 9px; }
.unread-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--ns-bg-e16b4c, #e16b4c); }
.delete-notification { margin: 0 13px; border: 0; padding: 6px; background: transparent; color: var(--ns-text-98a49b, #98a49b); cursor: pointer; }
.delete-notification:hover { color: var(--ns-text-b85138, #b85138); }
.secondary-action:disabled { cursor: not-allowed; opacity: .5; }
</style>
