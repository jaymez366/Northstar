<script setup lang="ts">
  import { computed, nextTick, ref, watch } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useWorkspaceStore } from '@/stores/workspace'

  const route = useRoute()
  const router = useRouter()
  const workspace = useWorkspaceStore()
  const search = ref('')
  const draft = ref('')
  const selectedId = ref(typeof route.query.conversation === 'string' ? route.query.conversation : '')
  const refreshing = ref(false)
  const refreshError = ref('')
  const sending = ref(false)
  const nearBottom = ref(true)
  const messageList = ref<HTMLElement | null>(null)
  const selectedConversation = computed(() => workspace.conversations.find(item => item.id === selectedId.value))
  const composingEmployee = computed(() => {
    const employeeId = typeof route.query.employee === 'string' ? route.query.employee : ''
    return employeeId ? workspace.employees.find(item => item.id === employeeId) : undefined
  })
  const displayEmployee = computed(() => selectedConversation.value ? {
    id: selectedConversation.value.employeeId,
    firstName: selectedConversation.value.name.split(' ')[0] ?? 'Colleague',
    lastName: selectedConversation.value.name.split(' ').slice(1).join(' '),
    title: selectedConversation.value.title,
    email: workspace.employees.find(item => item.id === selectedConversation.value?.employeeId)?.email ?? '',
    initials: selectedConversation.value.initials,
    color: selectedConversation.value.color,
  } : composingEmployee.value)
  const filteredConversations = computed(() => workspace.conversations.filter(item => item.name.toLowerCase().includes(search.value.trim().toLowerCase())))

  watch(() => [route.query.conversation, route.query.employee, workspace.conversations.length, workspace.employees.length], async () => {
    const conversationId = typeof route.query.conversation === 'string' ? route.query.conversation : ''
    if (conversationId) {
      if (workspace.conversations.some(item => item.id === conversationId)) selectedId.value = conversationId
      return
    }

    const employeeId = typeof route.query.employee === 'string' ? route.query.employee : ''
    if (!employeeId) {
      selectedId.value = ''
      return
    }

    const match = workspace.conversations.find(item => item.employeeId === employeeId)
    if (match) {
      selectedId.value = match.id
      await router.replace({ path: '/messages', query: { conversation: match.id } })
      return
    }

    selectedId.value = ''
  }, { immediate: true })

  watch(() => selectedConversation.value?.id, conversationId => {
    nearBottom.value = true
    if (conversationId) void workspace.markConversationRead(conversationId)
  }, { immediate: true })

  watch(() => selectedConversation.value?.messages.length, async (length, previousLength) => {
    if (selectedConversation.value && length !== previousLength) void workspace.markConversationRead(selectedConversation.value.id)
    if (length && previousLength !== undefined && length > previousLength && !nearBottom.value) return
    await nextTick()
    if (messageList.value) messageList.value.scrollTop = messageList.value.scrollHeight
  }, { immediate: true })

  function selectConversation (id: string) {
    selectedId.value = id
    void router.push({ path: '/messages', query: { conversation: id } })
  }

  function closeConversation () {
    selectedId.value = ''
    if (route.query.conversation || route.query.employee) {
      void router.replace({ path: '/messages' })
    }
  }

  async function send () {
    if ((!selectedConversation.value && !composingEmployee.value) || !draft.value.trim() || sending.value) return
    sending.value = true
    const sent = selectedConversation.value
      ? await workspace.sendMessage(selectedConversation.value.id, draft.value)
      : await workspace.sendFirstMessage(composingEmployee.value!.id, draft.value)
    if (sent) {
      draft.value = ''
      if (!selectedConversation.value) {
        const conversation = workspace.conversations.find(item => item.employeeId === composingEmployee.value?.id)
        if (conversation) {
          selectedId.value = conversation.id
          await router.replace({ path: '/messages', query: { conversation: conversation.id } })
        }
      }
    }
    sending.value = false
  }

  async function refreshMessages () {
    if (refreshing.value) return
    refreshing.value = true
    refreshError.value = ''
    try {
      const error = await workspace.refreshConversations()
      if (error) refreshError.value = error
      if (selectedId.value && !workspace.conversations.some(item => item.id === selectedId.value)) selectedId.value = ''
    } catch (error) {
      refreshError.value = error instanceof Error ? error.message : 'Messages could not be refreshed.'
    } finally {
      refreshing.value = false
    }
  }

  function trackMessageScroll () {
    if (!messageList.value) return
    nearBottom.value = messageList.value.scrollHeight - messageList.value.scrollTop - messageList.value.clientHeight < 80
  }
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">YOUR INBOX</p><h1>Messages</h1><p>Keep conversations moving with direct, thoughtful communication.</p></div><router-link class="secondary-action" to="/employees"><v-icon icon="mdi-plus" size="17" /> New message</router-link></header>

    <section class="messaging-layout surface-card" :class="{ 'has-selected-conversation': Boolean(selectedConversation || composingEmployee) }">
      <aside class="conversation-sidebar">
        <div class="inbox-heading"><strong>Inbox</strong><span>{{ workspace.conversations.length }}</span><button class="refresh-button" type="button" aria-label="Refresh messages" title="Refresh messages" :disabled="refreshing" @click="refreshMessages"><v-icon icon="mdi-refresh" :class="{ spinning: refreshing }" size="17" /></button></div>
        <p v-if="refreshError" class="refresh-error" role="alert">{{ refreshError }}</p>
        <p v-else-if="workspace.messageSyncError" class="refresh-error" role="alert">{{ workspace.messageSyncError }}</p>
        <input v-model="search" aria-label="Search conversations" class="field-control conversation-search" placeholder="Search conversations">

        <button
          v-for="conversation in filteredConversations"
          :key="conversation.id"
          class="conversation-item"
          :class="{ selected: selectedId === conversation.id }"
          @click="selectConversation(conversation.id)"
        >
          <span class="conversation-avatar" :style="{ background: conversation.color }">{{ conversation.initials }}<i v-if="conversation.online !== null" :class="{ online: conversation.online }" /></span>
          <span class="conversation-copy"><strong>{{ conversation.name }}</strong><small>{{ conversation.messages.at(-1)?.text }}</small></span>
          <span class="conversation-meta"><small>{{ conversation.updatedAt }}</small><b v-if="conversation.unread">{{ conversation.unread }}</b></span>
        </button>

        <div v-if="filteredConversations.length === 0" class="conversation-empty">
          <template v-if="workspace.conversations.length">No conversations match.</template>
          <template v-else>No conversations yet. Browse colleagues to start one.</template>
        </div>
      </aside>

      <section v-if="selectedConversation || composingEmployee" class="chat-panel">
        <header class="chat-header">
          <button class="conversation-back" type="button" @click="closeConversation">
            <v-icon icon="mdi-arrow-left" size="18" /> Back to inbox
          </button>
          <span class="conversation-avatar large" :style="{ background: displayEmployee?.color }">{{ displayEmployee?.initials }}</span>
          <span><strong>{{ displayEmployee?.firstName }} {{ displayEmployee?.lastName }}</strong><small>{{ selectedConversation?.title || composingEmployee?.title || 'New message' }}</small></span>
          <a v-if="displayEmployee?.email" class="chat-email" :href="`mailto:${displayEmployee.email}`"><v-icon icon="mdi-email-outline" size="19" /></a>
        </header>

        <div ref="messageList" class="message-list" @scroll="trackMessageScroll">
          <div class="conversation-date">TODAY</div>

          <p v-if="composingEmployee && !selectedConversation" class="first-message-hint">This is a temporary message draft. A conversation is created only when your first message is sent.</p>

          <article v-for="message in selectedConversation?.messages ?? []" :key="message.id" class="chat-message" :class="{ mine: message.mine }">
            <small v-if="!message.mine">{{ message.author }}</small>
            <p>{{ message.text }}</p>
            <time>{{ message.sentAt }}</time>
          </article>
        </div>

        <form class="composer" @submit.prevent="send">
          <input v-model="draft" aria-label="Write a message" autocomplete="off" placeholder="Write a message...">
          <button aria-label="Send message" :disabled="!draft.trim() || sending" type="submit"><v-icon icon="mdi-send" size="18" /></button>
        </form>
      </section>

      <section v-else class="chat-empty empty-state"><v-icon icon="mdi-message-text-outline" size="38" /><h2>Your messages</h2><p>Select an employee to open a conversation.</p><router-link class="secondary-action" to="/employees">Browse colleagues</router-link></section>
    </section>
  </main>
</template>

<style scoped>
.messaging-layout { display: grid; min-height: 570px; grid-template-columns: 310px minmax(0, 1fr); overflow: hidden; }
.conversation-sidebar { border-right: 1px solid var(--ns-border-e7ebe3, #e7ebe3); }
.inbox-heading { display: flex; align-items: center; gap: 9px; padding: 17px 17px 12px; color: var(--ns-text-18352d, #18352d); font-size: 13px; }
.refresh-button { display: grid; width: 30px; height: 30px; place-items: center; margin-left: auto; border: 1px solid var(--ns-border); border-radius: 8px; background: var(--ns-surface); color: var(--ns-primary); cursor: pointer; }
.refresh-button:disabled { cursor: wait; opacity: .65; }
.refresh-button .spinning { animation: refresh-spin .8s linear infinite; }
.refresh-error { margin: 0 14px 10px; color: var(--ns-danger-text); font-size: 11px; line-height: 1.5; }
@keyframes refresh-spin { to { transform: rotate(360deg); } }
.inbox-heading span { display: grid; width: 20px; height: 20px; place-items: center; border-radius: 50%; background: var(--ns-bg-eef2e8, #eef2e8); color: var(--ns-text-60776b, #60776b); font-size: 9px; }
.conversation-search { width: calc(100% - 30px); margin: 0 15px 10px; }
.conversation-item { display: flex; width: 100%; align-items: center; gap: 10px; border: 0; padding: 12px 14px; background: var(--ns-bg-fff, #fff); cursor: pointer; text-align: left; }
.conversation-item:hover, .conversation-item.selected { background: var(--ns-bg-f1f4eb, #f1f4eb); }
.conversation-avatar { position: relative; display: grid; flex: 0 0 40px; width: 40px; height: 40px; place-items: center; border-radius: 50%; color: var(--ns-text-18352d, #18352d); font-size: 10px; font-weight: 800; }
.conversation-avatar i { position: absolute; right: 0; bottom: 1px; width: 9px; height: 9px; border: 2px solid white; border-radius: 50%; background: var(--ns-bg-9ca89f, #9ca89f); }
.conversation-avatar i.online { background: var(--ns-bg-68a477, #68a477); }
.conversation-copy { display: grid; min-width: 0; flex: 1; gap: 5px; }
.conversation-copy strong { color: var(--ns-text-18352d, #18352d); font-size: 10px; }
.conversation-copy small { overflow: hidden; color: var(--ns-text-829187, #829187); text-overflow: ellipsis; font-size: 9px; white-space: nowrap; }
.conversation-meta { display: grid; justify-items: end; gap: 7px; color: var(--ns-text-9aa59d, #9aa59d); font-size: 8px; }
.conversation-meta b { display: grid; width: 17px; height: 17px; place-items: center; border-radius: 50%; background: var(--ns-bg-d4ec66, #d4ec66); color: var(--ns-text-18352d, #18352d); font-size: 8px; }
.conversation-empty { padding: 20px; color: var(--ns-text-829187, #829187); font-size: 10px; text-align: center; }
.chat-panel { display: flex; min-width: 0; flex-direction: column; }
.chat-header { display: flex; min-height: 69px; align-items: center; gap: 11px; padding: 12px 18px; border-bottom: 1px solid var(--ns-border-e7ebe3, #e7ebe3); }
.conversation-back { display: inline-flex; min-height: 36px; align-items: center; gap: 5px; border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 8px; padding: 0 9px; background: transparent; color: var(--ns-text-18352d, #18352d); cursor: pointer; font: inherit; font-size: 10px; }
.conversation-back:hover { background: var(--ns-bg-f1f4eb, #f1f4eb); }
.conversation-back:focus-visible { outline: 2px solid var(--ns-blue-primary, #2563eb); outline-offset: 2px; }
.chat-header > span:nth-child(2) { display: grid; gap: 4px; }
.chat-header strong { color: var(--ns-text-18352d, #18352d); font-size: 11px; }
.chat-header small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.conversation-avatar.large { flex-basis: 38px; width: 38px; height: 38px; }
.chat-email { margin-left: auto; color: var(--ns-text-71897b, #71897b); }
.message-list { display: flex; flex: 1; flex-direction: column; gap: 15px; overflow-y: auto; padding: 22px; }
.conversation-date { align-self: center; color: var(--ns-text-a1aaa2, #a1aaa2); font: 8px "DM Mono", monospace; letter-spacing: 1px; }
.first-message-hint { align-self: center; max-width: 360px; color: var(--ns-text-secondary); font-size: 11px; line-height: 1.6; text-align: center; }
.chat-message { max-width: min(78%, 430px); align-self: flex-start; }
.chat-message.mine { align-self: flex-end; text-align: right; }
.chat-message > small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.chat-message p { margin: 5px 0 4px; border: 1px solid var(--ns-border-e3e9dc, #e3e9dc); padding: 10px 13px; background: var(--ns-bg-f5f7f1, #f5f7f1); color: var(--ns-text-394d41, #394d41); text-align: left; font-size: 10px; line-height: 1.6; }
.chat-message.mine p { border-color: var(--ns-border-18352d, #18352d); background: var(--ns-bg-18352d, #18352d); color: var(--ns-text-f3f5ef, #f3f5ef); }
.chat-message time { color: var(--ns-text-a1aaa2, #a1aaa2); font-size: 8px; }
.composer { display: flex; gap: 8px; margin: 0 17px 17px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); padding: 6px; }
.composer input { min-width: 0; flex: 1; border: 0; outline: none; padding: 8px; color: var(--ns-text-18352d, #18352d); font: 11px "Manrope", sans-serif; }
.composer button { display: grid; width: 36px; height: 34px; place-items: center; border: 0; background: var(--ns-bg-d4ec66, #d4ec66); color: var(--ns-text-18352d, #18352d); cursor: pointer; }
.composer button:disabled { cursor: not-allowed; opacity: .5; }
.chat-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 35px; }
.chat-empty .secondary-action { margin-top: 6px; }
@media (max-width: 760px) {
  .messaging-layout { min-height: 620px; grid-template-columns: 1fr; }
  .conversation-sidebar { max-height: 220px; overflow: auto; border-right: 0; border-bottom: 1px solid var(--ns-border-e7ebe3, #e7ebe3); }
  .messaging-layout.has-selected-conversation .conversation-sidebar { display: none; }
  .messaging-layout.has-selected-conversation .chat-panel { min-height: 540px; }
  .chat-header { flex-wrap: wrap; gap: 9px; padding: 12px; }
  .conversation-back { flex: 0 0 auto; }
  .chat-email { margin-left: auto; }
  .chat-panel { min-height: 390px; }
}
</style>
