<script setup lang="ts">
  import { computed, nextTick, ref, watch } from 'vue'
  import { useRoute } from 'vue-router'
  import { useWorkspaceStore } from '@/stores/workspace'

  const route = useRoute()
  const workspace = useWorkspaceStore()
  const search = ref('')
  const draft = ref('')
  const selectedId = ref(workspace.conversations.find(item => item.employeeId === route.query.employee)?.id ?? workspace.conversations[0]?.id ?? '')
  const messageList = ref<HTMLElement | null>(null)
  const selectedConversation = computed(() => workspace.conversations.find(item => item.id === selectedId.value))
  const filteredConversations = computed(() => workspace.conversations.filter(item => item.name.toLowerCase().includes(search.value.trim().toLowerCase())))

  watch(() => route.query.employee, employeeId => {
    if (typeof employeeId !== 'string') return
    const match = workspace.conversations.find(item => item.employeeId === employeeId)
    if (match) {
      selectedId.value = match.id
      return
    }
    void workspace.startConversation(employeeId).then(id => {
      if (id) selectedId.value = id
    })
  })

  watch(selectedId, conversationId => {
    if (conversationId) void workspace.markConversationRead(conversationId)
  }, { immediate: true })

  watch(() => selectedConversation.value?.messages.length, async () => {
    await nextTick()
    if (messageList.value) messageList.value.scrollTop = messageList.value.scrollHeight
  }, { immediate: true })

  function selectConversation (id: string) {
    selectedId.value = id
  }

  async function send () {
    if (!selectedConversation.value || !draft.value.trim()) return
    if (await workspace.sendMessage(selectedConversation.value.id, draft.value)) {
      draft.value = ''
    }
  }
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">YOUR INBOX</p><h1>Messages</h1><p>Keep conversations moving with direct, thoughtful communication.</p></div><router-link class="secondary-action" to="/employees"><v-icon icon="mdi-plus" size="17" /> New message</router-link></header>

    <section class="messaging-layout surface-card">
      <aside class="conversation-sidebar">
        <div class="inbox-heading"><strong>Inbox</strong><span>{{ workspace.conversations.length }}</span></div>
        <input v-model="search" aria-label="Search conversations" class="field-control conversation-search" placeholder="Search conversations">

        <button
          v-for="conversation in filteredConversations"
          :key="conversation.id"
          class="conversation-item"
          :class="{ selected: selectedId === conversation.id }"
          @click="selectConversation(conversation.id)"
        >
          <span class="conversation-avatar" :style="{ background: conversation.color }">{{ conversation.initials }}<i :class="{ online: conversation.online }" /></span>
          <span class="conversation-copy"><strong>{{ conversation.name }}</strong><small>{{ conversation.messages.at(-1)?.text }}</small></span>
          <span class="conversation-meta"><small>{{ conversation.updatedAt }}</small><b v-if="conversation.unread">{{ conversation.unread }}</b></span>
        </button>

        <div v-if="filteredConversations.length === 0" class="conversation-empty">No conversations match.</div>
      </aside>

      <section v-if="selectedConversation" class="chat-panel">
        <header class="chat-header">
          <span class="conversation-avatar large" :style="{ background: selectedConversation?.color }">{{ selectedConversation?.initials }}<i :class="{ online: selectedConversation?.online }" /></span>
          <span><strong>{{ selectedConversation?.name }}</strong><small>{{ selectedConversation?.online ? 'Online now' : selectedConversation?.title }}</small></span>
          <a class="chat-email" :href="`mailto:${workspace.employees.find(item => item.id === selectedConversation?.employeeId)?.email}`"><v-icon icon="mdi-email-outline" size="19" /></a>
        </header>

        <div ref="messageList" class="message-list">
          <div class="conversation-date">TODAY</div>

          <article v-for="message in selectedConversation?.messages ?? []" :key="message.id" class="chat-message" :class="{ mine: message.mine }">
            <small v-if="!message.mine">{{ message.author }}</small>
            <p>{{ message.text }}</p>
            <time>{{ message.sentAt }}</time>
          </article>
        </div>

        <form class="composer" @submit.prevent="send">
          <input v-model="draft" aria-label="Write a message" autocomplete="off" placeholder="Write a message...">
          <button aria-label="Send message" :disabled="!draft.trim()" type="submit"><v-icon icon="mdi-send" size="18" /></button>
        </form>
      </section>

      <section v-else class="chat-empty empty-state"><v-icon icon="mdi-message-text-outline" size="38" /><h2>Your conversations</h2><p>Select a conversation to read and reply, or find a colleague to start a new one.</p><router-link class="secondary-action" to="/employees">Browse colleagues</router-link></section>
    </section>
  </main>
</template>

<style scoped>
.messaging-layout { display: grid; min-height: 570px; grid-template-columns: 310px 1fr; overflow: hidden; }
.conversation-sidebar { border-right: 1px solid #e7ebe3; }
.inbox-heading { display: flex; align-items: center; gap: 9px; padding: 17px 17px 12px; color: #18352d; font-size: 13px; }
.inbox-heading span { display: grid; width: 20px; height: 20px; place-items: center; border-radius: 50%; background: #eef2e8; color: #60776b; font-size: 9px; }
.conversation-search { width: calc(100% - 30px); margin: 0 15px 10px; }
.conversation-item { display: flex; width: 100%; align-items: center; gap: 10px; border: 0; padding: 12px 14px; background: #fff; cursor: pointer; text-align: left; }
.conversation-item:hover, .conversation-item.selected { background: #f1f4eb; }
.conversation-avatar { position: relative; display: grid; flex: 0 0 40px; width: 40px; height: 40px; place-items: center; border-radius: 50%; color: #18352d; font-size: 10px; font-weight: 800; }
.conversation-avatar i { position: absolute; right: 0; bottom: 1px; width: 9px; height: 9px; border: 2px solid white; border-radius: 50%; background: #9ca89f; }
.conversation-avatar i.online { background: #68a477; }
.conversation-copy { display: grid; min-width: 0; flex: 1; gap: 5px; }
.conversation-copy strong { color: #18352d; font-size: 10px; }
.conversation-copy small { overflow: hidden; color: #829187; text-overflow: ellipsis; font-size: 9px; white-space: nowrap; }
.conversation-meta { display: grid; justify-items: end; gap: 7px; color: #9aa59d; font-size: 8px; }
.conversation-meta b { display: grid; width: 17px; height: 17px; place-items: center; border-radius: 50%; background: #d4ec66; color: #18352d; font-size: 8px; }
.conversation-empty { padding: 20px; color: #829187; font-size: 10px; text-align: center; }
.chat-panel { display: flex; min-width: 0; flex-direction: column; }
.chat-header { display: flex; min-height: 69px; align-items: center; gap: 11px; padding: 12px 18px; border-bottom: 1px solid #e7ebe3; }
.chat-header > span:nth-child(2) { display: grid; gap: 4px; }
.chat-header strong { color: #18352d; font-size: 11px; }
.chat-header small { color: #829187; font-size: 9px; }
.conversation-avatar.large { flex-basis: 38px; width: 38px; height: 38px; }
.chat-email { margin-left: auto; color: #71897b; }
.message-list { display: flex; flex: 1; flex-direction: column; gap: 15px; overflow-y: auto; padding: 22px; }
.conversation-date { align-self: center; color: #a1aaa2; font: 8px "DM Mono", monospace; letter-spacing: 1px; }
.chat-message { max-width: min(78%, 430px); align-self: flex-start; }
.chat-message.mine { align-self: flex-end; text-align: right; }
.chat-message > small { color: #829187; font-size: 9px; }
.chat-message p { margin: 5px 0 4px; border: 1px solid #e3e9dc; padding: 10px 13px; background: #f5f7f1; color: #394d41; text-align: left; font-size: 10px; line-height: 1.6; }
.chat-message.mine p { border-color: #18352d; background: #18352d; color: #f3f5ef; }
.chat-message time { color: #a1aaa2; font-size: 8px; }
.composer { display: flex; gap: 8px; margin: 0 17px 17px; border: 1px solid #dce4d8; padding: 6px; }
.composer input { min-width: 0; flex: 1; border: 0; outline: none; padding: 8px; color: #18352d; font: 11px "Manrope", sans-serif; }
.composer button { display: grid; width: 36px; height: 34px; place-items: center; border: 0; background: #d4ec66; color: #18352d; cursor: pointer; }
.composer button:disabled { cursor: not-allowed; opacity: .5; }
.chat-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 35px; }
.chat-empty .secondary-action { margin-top: 6px; }
@media (max-width: 760px) {
  .messaging-layout { min-height: 620px; grid-template-columns: 1fr; }
  .conversation-sidebar { max-height: 220px; overflow: auto; border-right: 0; border-bottom: 1px solid #e7ebe3; }
  .chat-panel { min-height: 390px; }
}
</style>
