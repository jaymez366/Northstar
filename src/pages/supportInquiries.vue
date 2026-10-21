<script setup lang="ts">
  import { computed, onMounted, onUnmounted, ref } from 'vue'
  import { useAuthStore } from '@/stores/auth'
  import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

  type Inquiry = { id: string, topic: string, status: string, created_at: string, updated_at: string }
  type InquiryMessage = { id: string, sender_id: string, sender_name: string, content: string, created_at: string }

  const inquiries = ref<Inquiry[]>([])
  const auth = useAuthStore()
  const selectedId = ref('')
  const messages = ref<InquiryMessage[]>([])
  const reply = ref('')
  const loading = ref(false)
  const sending = ref(false)
  const error = ref('')
  const messagesLoading = ref(false)
  let refreshTimer: number | undefined
  const selectedInquiry = computed(() => inquiries.value.find(inquiry => inquiry.id === selectedId.value))
  const isUuid = (value: string | null | undefined): value is string =>
    typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)

  async function loadInquiries () {
    if (loading.value) return
    if (!isSupabaseConfigured || !supabase) {
      error.value = 'Support conversations are unavailable because Northstar Supabase is not configured.'
      inquiries.value = []
      messages.value = []
      return
    }
    loading.value = true
    error.value = ''
    try {
      const { data, error: loadError } = await supabase.rpc('northstar_list_my_support_inquiries')
      if (loadError) {
        error.value = `Could not load your support inquiries: ${loadError.message}`
        console.error(error.value, loadError)
      } else {
        inquiries.value = data ?? []
        if (!selectedId.value && inquiries.value[0]) selectedId.value = inquiries.value[0].id
        if (selectedId.value && inquiries.value.some(inquiry => inquiry.id === selectedId.value)) {
          await loadMessages(selectedId.value)
        } else {
          selectedId.value = ''
          messages.value = []
        }
      }
    } catch (loadError) {
      error.value = 'Could not load your support inquiries. Please try again.'
      console.error(error.value, loadError)
    } finally {
      loading.value = false
    }
  }

  async function loadMessages (inquiryId: string) {
    if (!supabase || !isUuid(inquiryId)) return
    selectedId.value = inquiryId
    error.value = ''
    messagesLoading.value = true
    try {
      const { data, error: loadError } = await supabase.rpc('northstar_get_support_inquiry_messages', { p_inquiry_id: inquiryId })
      if (loadError) {
        error.value = `Could not load inquiry messages: ${loadError.message}`
        console.error(error.value, loadError)
      } else if (selectedId.value === inquiryId) {
        messages.value = data ?? []
      }
    } catch (loadError) {
      error.value = 'Could not load inquiry messages. Please try again.'
      console.error(error.value, loadError)
    } finally {
      messagesLoading.value = false
    }
  }

  async function sendReply () {
    const content = reply.value.trim()
    if (!isUuid(selectedId.value) || !content || sending.value || !supabase) return
    sending.value = true
    error.value = ''
    try {
      const { error: sendError } = await supabase.rpc('northstar_reply_support_inquiry', {
        p_inquiry_id: selectedId.value,
        p_message: content,
      })
      if (sendError) {
        error.value = `Could not send your reply: ${sendError.message}`
        console.error(error.value, sendError)
      } else {
        reply.value = ''
        await loadInquiries()
      }
    } catch (sendError) {
      error.value = 'Could not send your reply. Please try again.'
      console.error(error.value, sendError)
    } finally {
      sending.value = false
    }
  }

  function formatDate (value: string) {
    return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  }

  onMounted(() => {
    void loadInquiries()
    refreshTimer = window.setInterval(() => { void loadInquiries() }, 20_000)
  })

  onUnmounted(() => {
    if (refreshTimer !== undefined) window.clearInterval(refreshTimer)
  })
</script>

<template>
  <main>
    <header class="page-heading">
      <div><p class="eyebrow">TALK TO AN EXPERT</p><h1>Support inquiries</h1><p>Read replies from the Northstar support team and continue the conversation.</p></div>
      <button class="secondary-action" :disabled="loading" type="button" @click="loadInquiries">{{ loading ? 'Refreshing…' : 'Refresh' }}</button>
    </header>

    <p v-if="error" class="support-error" role="alert">{{ error }}</p>
    <section class="support-layout surface-card">
      <aside class="support-list">
        <button v-for="inquiry in inquiries" :key="inquiry.id" class="support-item" :class="{ selected: selectedId === inquiry.id }" type="button" @click="loadMessages(inquiry.id)">
          <strong>{{ inquiry.topic }}</strong><small>{{ inquiry.status }} · {{ formatDate(inquiry.created_at) }}</small>
        </button>
        <p v-if="loading && inquiries.length === 0" class="support-empty" role="status">Loading your conversations…</p>
        <p v-else-if="!loading && inquiries.length === 0" class="support-empty">You have no support inquiries yet.</p>
      </aside>

      <section v-if="selectedInquiry" class="support-thread">
        <h2>{{ selectedInquiry.topic }}</h2>
        <p class="thread-refresh-note">Messages refresh automatically. You can also refresh the list above.</p>
        <div class="support-messages">
          <p v-if="messagesLoading" class="support-empty" role="status">Loading messages…</p>
          <p v-else-if="messages.length === 0" class="support-empty">This conversation has no messages yet.</p>
          <article v-for="message in messages" v-else :key="message.id" class="support-message" :class="{ mine: message.sender_id === auth.userId }">
            <strong>{{ message.sender_name }}</strong><p>{{ message.content }}</p><time>{{ formatDate(message.created_at) }}</time>
          </article>
        </div>
        <form class="support-reply" @submit.prevent="sendReply">
          <textarea v-model="reply" aria-label="Reply to support inquiry" maxlength="5000" placeholder="Write a reply…" rows="3" />
          <button class="primary-action" :disabled="!reply.trim() || sending" type="submit">
            <v-progress-circular v-if="sending" aria-label="Sending reply" indeterminate size="16" width="2" />
            {{ sending ? 'Sending…' : 'Send reply' }}
          </button>
        </form>
      </section>
      <section v-else class="support-empty support-thread">Select an inquiry to view messages.</section>
    </section>
  </main>
</template>

<style scoped>
.support-layout { display: grid; min-height: 480px; grid-template-columns: 280px 1fr; overflow: hidden; }
.support-list { border-right: 1px solid var(--ns-border-e7ebe3, #e7ebe3); }
.support-item { display: grid; width: 100%; gap: 7px; border: 0; border-bottom: 1px solid var(--ns-border-edf0ea, #edf0ea); padding: 15px; background: white; color: var(--ns-text-18352d, #18352d); cursor: pointer; text-align: left; }
.support-item.selected { background: var(--ns-bg-f1f4eb, #f1f4eb); }
.support-item small, .support-empty { color: var(--ns-text-829187, #829187); font-size: 10px; }
.support-thread { display: flex; min-width: 0; flex-direction: column; padding: 20px; }
.support-thread h2 { margin: 0 0 15px; color: var(--ns-text-18352d, #18352d); font-size: 16px; }
.support-messages { display: flex; flex: 1; flex-direction: column; gap: 12px; overflow-y: auto; }
.support-message { border: 1px solid var(--ns-border-e3e9dc, #e3e9dc); padding: 12px; background: var(--ns-bg-f8f9f6, #f8f9f6); }
.support-message strong { color: var(--ns-text-18352d, #18352d); font-size: 11px; }
.support-message p { margin: 6px 0; color: var(--ns-text-52645a, #52645a); font-size: 12px; white-space: pre-wrap; }
.support-message time { color: var(--ns-text-829187, #829187); font-size: 9px; }
.support-reply { display: grid; gap: 10px; margin-top: 16px; }
.support-reply textarea { border: 1px solid var(--ns-border-dce4d8, #dce4d8); padding: 10px; color: var(--ns-text-18352d, #18352d); font: inherit; }
.support-reply button { justify-self: end; }
.support-error { color: var(--ns-text-a34c39, #a34c39); font-size: 12px; }
.thread-refresh-note { margin: -10px 0 12px; color: var(--ns-text-secondary); font-size: 10px; }
.support-message.mine { align-self: flex-end; max-width: 85%; border-color: var(--ns-blue-border); background: var(--ns-blue-soft); }
@media (max-width: 700px) { .support-layout { grid-template-columns: 1fr; } .support-list { max-height: 220px; overflow: auto; border-right: 0; border-bottom: 1px solid var(--ns-border-e7ebe3, #e7ebe3); } .support-thread { min-height: 360px; } }
</style>
