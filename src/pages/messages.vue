<script setup lang="ts">
  import { computed, nextTick, onUnmounted, ref, watch } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useCallsStore } from '@/stores/calls'
  import { useWorkspaceStore } from '@/stores/workspace'

  const route = useRoute()
  const router = useRouter()
  const workspace = useWorkspaceStore()
  const calls = useCallsStore()
  const search = ref('')
  const showArchived = ref(false)
  const draft = ref('')
  const selectedId = ref(typeof route.query.conversation === 'string' ? route.query.conversation : '')
  const refreshing = ref(false)
  const refreshError = ref('')
  const sending = ref(false)
  const nearBottom = ref(true)
  const messageList = ref<HTMLElement | null>(null)
  const editingMessageId = ref('')
  const editDraft = ref('')
  const selectedMessageIds = ref<string[]>([])
  const openMenuMessageId = ref('')
  const messageSearchOpen = ref(false)
  const messageSearch = ref('')
  const activeSearchMessageId = ref('')
  const actionNotice = ref('')
  const replyingTo = ref<{ id: string, author: string, text: string } | null>(null)
  const reactionOptions = ['👍', '❤️', '😂', '😮', '😢', '🙏']
  const attachmentInput = ref<HTMLInputElement | null>(null)
  const selectedAttachment = ref<File | null>(null)
  const attachmentUrls = ref<Record<string, string>>({})
  const uploadProgress = ref(0)
  const uploadingAttachment = ref(false)
  const recordingVoice = ref(false)
  const recordingPaused = ref(false)
  const recordingSeconds = ref(0)
  const dictating = ref(false)
  const recordedVoiceFile = ref<File | null>(null)
  const recordedVoiceUrl = ref('')
  const searchResultIndex = ref(0)
  let suppressNextMessageClick = ''
  let longPressTimer: ReturnType<typeof setTimeout> | undefined
  let pressOrigin: { x: number, y: number } | undefined
  let uploadController: AbortController | null = null
  let typingStopTimer: ReturnType<typeof setTimeout> | undefined
  let recorder: MediaRecorder | null = null
  let recordingStream: MediaStream | null = null
  let recordingTimer: ReturnType<typeof setInterval> | undefined
  let recordingElapsedMs = 0
  let recordingResumedAt = 0
  let recognition: SpeechRecognitionLike | null = null
  let discardRecording = false
  let pageIsUnmounting = false
  const acknowledgedVisibleMessageVersions = new Set<string>()
  const pendingVisibleAcknowledgementVersions = new Set<string>()
  const visibilityChangeHandler = () => observeVisibleMessages()
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
  const filteredConversations = computed(() => workspace.conversations
    .filter(item => item.archived === showArchived.value)
    .filter(item => item.name.toLowerCase().includes(search.value.trim().toLowerCase())))
  const pinnedMessages = computed(() => (selectedConversation.value?.pinnedMessageIds ?? [])
    .map(id => selectedConversation.value?.messages.find(message => message.id === id))
    .filter((message): message is NonNullable<typeof message> => Boolean(message)))
  const typingLabel = computed(() => {
    const users = selectedConversation.value?.typingUserIds ?? []
    if (!users.length) return ''
    const names = users.map(id => workspace.employees.find(employee => employee.id === id)?.firstName).filter(Boolean)
    return names.length ? `${names.join(', ')} ${names.length === 1 ? 'is' : 'are'} typing…` : 'Someone is typing…'
  })
  let visibilityObserver: IntersectionObserver | null = null

  interface SpeechRecognitionLike {
    continuous: boolean
    interimResults: boolean
    lang: string
    onresult: ((event: { resultIndex: number, results: ArrayLike<{ isFinal: boolean, 0: { transcript: string } }> }) => void) | null
    onerror: ((event: { error: string }) => void) | null
    onend: (() => void) | null
    start: () => void
    stop: () => void
    abort: () => void
  }
  type SpeechRecognitionWindow = Window & {
    SpeechRecognition?: new () => SpeechRecognitionLike
    webkitSpeechRecognition?: new () => SpeechRecognitionLike
  }

  if (typeof IntersectionObserver !== 'undefined') {
    visibilityObserver = new IntersectionObserver(entries => {
      for (const entry of entries) {
        const element = entry.target as HTMLElement
        const messageId = element.dataset.messageId ?? ''
        const messageVersion = Number(element.dataset.messageVersion)
        const receiptKey = `${messageId}:${messageVersion}`
        const message = selectedConversation.value?.messages.find(item => item.id === messageId)
        if (!message || message.contentVersion !== messageVersion || message.mine || message.deletedAt || entry.intersectionRatio < 0.75 || document.visibilityState !== 'visible' || pendingVisibleAcknowledgementVersions.has(receiptKey) || acknowledgedVisibleMessageVersions.has(receiptKey)) continue
        pendingVisibleAcknowledgementVersions.add(receiptKey)
        void workspace.acknowledgeMessageVisible(messageId, messageVersion).then(acknowledged => {
          if (acknowledged) acknowledgedVisibleMessageVersions.add(receiptKey)
        }).finally(() => pendingVisibleAcknowledgementVersions.delete(receiptKey))
      }
    }, { root: null, threshold: [0.75] })
  }

  function observeVisibleMessages () {
    if (!visibilityObserver || !messageList.value) return
    visibilityObserver.disconnect()
    if (document.visibilityState !== 'visible') return
    messageList.value.querySelectorAll<HTMLElement>('[data-message-id]').forEach(element => visibilityObserver?.observe(element))
  }

  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', visibilityChangeHandler)

  watch(() => [selectedConversation.value?.id, selectedConversation.value?.messages.map(message => `${message.id}:${message.contentVersion}`).join('|')], async () => {
    await nextTick()
    observeVisibleMessages()
  }, { immediate: true })

  onUnmounted(() => {
    pageIsUnmounting = true
    uploadController?.abort()
    if (typingStopTimer) clearTimeout(typingStopTimer)
    if (selectedConversation.value) void workspace.updateConversationTyping(selectedConversation.value.id, false)
    stopVoiceRecording(true)
    recognition?.abort()
    recognition = null
    if (recordedVoiceUrl.value) URL.revokeObjectURL(recordedVoiceUrl.value)
    for (const url of Object.values(attachmentUrls.value)) URL.revokeObjectURL(url)
    cancelMessagePress()
    visibilityObserver?.disconnect()
    if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', visibilityChangeHandler)
    if (typeof window !== 'undefined') window.removeEventListener('keydown', onGlobalKeydown)
  })

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

  watch(() => selectedConversation.value?.id, (conversationId, previousId) => {
    if (previousId && previousId !== conversationId) void workspace.updateConversationTyping(previousId, false)
    nearBottom.value = true
    replyingTo.value = null
    selectedMessageIds.value = []
    openMenuMessageId.value = ''
    messageSearch.value = ''
    messageSearchOpen.value = false
    if (conversationId) void workspace.markConversationRead(conversationId)
  }, { immediate: true })

  const messageSearchResults = computed(() => {
    const term = messageSearch.value.trim().toLocaleLowerCase()
    if (!term) return []
    return (selectedConversation.value?.messages ?? []).filter(message => !message.callEvent && !message.deletedAt && message.text.toLocaleLowerCase().includes(term))
  })
  watch(messageSearch, () => { searchResultIndex.value = 0 })

  watch(() => selectedConversation.value?.messages.filter(message => !message.callEvent).length, async (length, previousLength) => {
    if (selectedConversation.value && length !== previousLength) void workspace.markConversationRead(selectedConversation.value.id)
    if (length && previousLength !== undefined && length > previousLength && !nearBottom.value) return
    await nextTick()
    if (messageList.value) messageList.value.scrollTop = messageList.value.scrollHeight
  }, { immediate: true })

  function selectConversation (id: string) {
    selectedId.value = id
    replyingTo.value = null
    void router.push({ path: '/messages', query: { conversation: id } })
  }

  function closeConversation () {
    if (selectedConversation.value) void workspace.updateConversationTyping(selectedConversation.value.id, false)
    selectedId.value = ''
    replyingTo.value = null
    if (route.query.conversation || route.query.employee) {
      void router.replace({ path: '/messages' })
    }
  }

  function handleComposerInput () {
    const conversationId = selectedConversation.value?.id
    if (!conversationId) return
    if (typingStopTimer) clearTimeout(typingStopTimer)
    if (!draft.value.trim()) {
      void workspace.updateConversationTyping(conversationId, false)
      return
    }
    void workspace.updateConversationTyping(conversationId, true)
    typingStopTimer = setTimeout(() => {
      void workspace.updateConversationTyping(conversationId, false)
      typingStopTimer = undefined
    }, 2500)
  }

  async function markCurrentConversationUnread () {
    const conversationId = selectedConversation.value?.id
    if (!conversationId) return
    if (await workspace.setConversationState(conversationId, 'mark_unread')) closeConversation()
  }

  async function togglePinnedMessage (messageId: string) {
    const conversation = selectedConversation.value
    if (!conversation) return
    const isPinned = conversation.pinnedMessageIds.includes(messageId)
    if (!await workspace.setMessagePinned(conversation.id, messageId, !isPinned)) {
      actionNotice.value = workspace.backendError || 'Could not update this pin.'
      return
    }
    actionNotice.value = isPinned ? 'Message unpinned for you.' : 'Message pinned for you.'
    window.setTimeout(() => { actionNotice.value = '' }, 2500)
  }

  function startConversationCall (kind: 'audio' | 'video') {
    if (!selectedConversation.value) return
    void calls.startCall(selectedConversation.value.id, kind)
  }

  async function send () {
    if ((!selectedConversation.value && !composingEmployee.value) || !draft.value.trim() || sending.value || uploadingAttachment.value || recordingVoice.value || selectedAttachment.value || recordedVoiceFile.value) return
    sending.value = true
    const sent = selectedConversation.value
      ? await workspace.sendMessage(selectedConversation.value.id, draft.value, replyingTo.value?.id)
      : await workspace.sendFirstMessage(composingEmployee.value!.id, draft.value)
    if (sent) {
      draft.value = ''
      replyingTo.value = null
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

  function chooseAttachment (event: Event) {
    const input = event.target as HTMLInputElement
    selectedAttachment.value = input.files?.[0] ?? null
    uploadProgress.value = 0
  }

  function formatDuration (seconds: number) {
    const safeSeconds = Math.max(0, Math.floor(seconds))
    return `${Math.floor(safeSeconds / 60)}:${String(safeSeconds % 60).padStart(2, '0')}`
  }

  function formatCallDuration (seconds: number) {
    const safeSeconds = Math.max(0, Math.floor(seconds))
    if (safeSeconds < 60) return `${safeSeconds} sec`
    const minutes = Math.floor(safeSeconds / 60)
    if (minutes < 60) return `${minutes} min ${safeSeconds % 60} sec`
    const hours = Math.floor(minutes / 60)
    const remainingMinutes = minutes % 60
    return `${hours} hr${hours === 1 ? '' : 's'}${remainingMinutes ? ` ${remainingMinutes} min` : ''}`
  }

  function formatBytes (bytes: number) {
    return bytes < 1024 * 1024 ? `${Math.ceil(bytes / 1024)} KB` : `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  async function uploadChatFile (file: File, durationSeconds: number | null = null) {
    if ((!selectedConversation.value && !composingEmployee.value) || uploadingAttachment.value) return
    let conversationId = selectedConversation.value?.id ?? ''
    if (!conversationId && composingEmployee.value) conversationId = await workspace.startConversation(composingEmployee.value.id)
    if (!conversationId) {
      actionNotice.value = workspace.backendError || 'Could not open a conversation for this attachment.'
      return
    }
    uploadController = new AbortController()
    uploadingAttachment.value = true
    uploadProgress.value = 0
    actionNotice.value = ''
    try {
      const sent = await workspace.sendMessageAttachment(conversationId, file, draft.value, durationSeconds, value => { uploadProgress.value = value }, uploadController.signal)
      if (!sent) {
        actionNotice.value = workspace.backendError || 'The attachment was not sent.'
        return
      }
      draft.value = ''
      selectedAttachment.value = null
      if (attachmentInput.value) attachmentInput.value.value = ''
      if (recordedVoiceUrl.value) URL.revokeObjectURL(recordedVoiceUrl.value)
      recordedVoiceUrl.value = ''
      recordedVoiceFile.value = null
      if (!selectedConversation.value) {
        await workspace.refreshConversations()
        const created = workspace.conversations.find(item => item.employeeId === composingEmployee.value?.id)
        if (created) {
          selectedId.value = created.id
          await router.replace({ path: '/messages', query: { conversation: created.id } })
        }
      }
    } catch (error) {
      actionNotice.value = error instanceof Error ? error.message : 'The attachment upload failed.'
    } finally {
      uploadingAttachment.value = false
      uploadController = null
    }
  }

  function cancelAttachmentUpload () {
    uploadController?.abort()
  }

  async function startVoiceRecording () {
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      actionNotice.value = 'Voice recording is not supported by this browser.'
      return
    }
    if (!window.isSecureContext) {
      actionNotice.value = 'Voice recording requires a secure HTTPS connection.'
      return
    }
    try {
      recordingStream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const preferredType = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'].find(type => MediaRecorder.isTypeSupported(type))
      recorder = new MediaRecorder(recordingStream, preferredType ? { mimeType: preferredType } : undefined)
      const chunks: BlobPart[] = []
      discardRecording = false
      recordingElapsedMs = 0
      recordingResumedAt = Date.now()
      recordingSeconds.value = 0
      recordingPaused.value = false
      recorder.ondataavailable = event => { if (event.data.size) chunks.push(event.data) }
      recorder.onstop = () => {
        recordingStream?.getTracks().forEach(track => track.stop())
        recordingStream = null
        if (!discardRecording && !pageIsUnmounting) {
          const blob = new Blob(chunks, { type: recorder?.mimeType || 'audio/webm' })
          if (blob.size) {
            const mimeType = blob.type.split(';')[0] || 'audio/webm'
            const extension = mimeType === 'audio/mp4' ? 'm4a' : mimeType === 'audio/ogg' ? 'ogg' : 'webm'
            recordedVoiceFile.value = new File([blob], `voice-message-${Date.now()}.${extension}`, { type: mimeType })
            if (recordedVoiceUrl.value) URL.revokeObjectURL(recordedVoiceUrl.value)
            recordedVoiceUrl.value = URL.createObjectURL(blob)
            recordingSeconds.value = Math.ceil(recordingElapsedMs / 1000)
          }
        }
        recorder = null
        recordingVoice.value = false
        recordingPaused.value = false
      }
      recorder.onerror = () => { actionNotice.value = 'Recording stopped because the microphone failed.' }
      recorder.start(250)
      recordingVoice.value = true
      recordingTimer = setInterval(() => {
        const elapsed = recordingElapsedMs + (recordingPaused.value ? 0 : Date.now() - recordingResumedAt)
        recordingSeconds.value = Math.floor(elapsed / 1000)
        if (recordingSeconds.value >= 300) stopVoiceRecording(false)
      }, 250)
      actionNotice.value = ''
    } catch (error) {
      recordingStream?.getTracks().forEach(track => track.stop())
      recordingStream = null
      actionNotice.value = error instanceof Error ? `Microphone unavailable: ${error.message}` : 'Microphone permission was denied.'
    }
  }

  function stopVoiceRecording (cancel: boolean) {
    discardRecording = cancel
    if (recorder && recorder.state === 'recording') recordingElapsedMs += Date.now() - recordingResumedAt
    recordingSeconds.value = Math.ceil(recordingElapsedMs / 1000)
    if (recordingTimer) clearInterval(recordingTimer)
    recordingTimer = undefined
    if (recorder && recorder.state !== 'inactive') recorder.stop()
    else {
      recordingStream?.getTracks().forEach(track => track.stop())
      recordingStream = null
      recordingVoice.value = false
      recordingPaused.value = false
    }
    if (cancel) {
      recordedVoiceFile.value = null
      if (recordedVoiceUrl.value) URL.revokeObjectURL(recordedVoiceUrl.value)
      recordedVoiceUrl.value = ''
    }
  }

  function toggleVoiceRecordingPause () {
    if (!recorder || typeof recorder.pause !== 'function' || typeof recorder.resume !== 'function') {
      actionNotice.value = 'Pause and resume are not supported by this browser.'
      return
    }
    if (recorder.state === 'recording') {
      recordingElapsedMs += Date.now() - recordingResumedAt
      recorder.pause()
      recordingPaused.value = true
    } else if (recorder.state === 'paused') {
      recordingResumedAt = Date.now()
      recorder.resume()
      recordingPaused.value = false
    }
  }

  function toggleDictation () {
    if (recognition) {
      recognition.stop()
      return
    }
    const Recognition = (window as SpeechRecognitionWindow).SpeechRecognition
      ?? (window as SpeechRecognitionWindow).webkitSpeechRecognition
    if (!Recognition) {
      actionNotice.value = 'Speech-to-text is not supported by this browser.'
      return
    }
    try {
      const activeRecognition = new Recognition()
      recognition = activeRecognition
      activeRecognition.continuous = true
      activeRecognition.interimResults = false
      activeRecognition.lang = navigator.language || 'en'
      activeRecognition.onresult = event => {
        const transcript = Array.from(event.results).slice(event.resultIndex)
          .filter(result => result.isFinal)
          .map(result => result[0]?.transcript.trim())
          .filter(Boolean)
          .join(' ')
        if (transcript) draft.value = `${draft.value}${draft.value.trim() ? ' ' : ''}${transcript}`
      }
      activeRecognition.onerror = event => {
        actionNotice.value = event.error === 'not-allowed' || event.error === 'service-not-allowed'
          ? 'Microphone permission for speech-to-text was denied.'
          : `Speech-to-text stopped: ${event.error}.`
        recognition = null
        dictating.value = false
      }
      activeRecognition.onend = () => {
        if (recognition === activeRecognition) recognition = null
        dictating.value = false
      }
      activeRecognition.start()
      dictating.value = true
      actionNotice.value = 'Dictation is active. Review the text before sending.'
    } catch (reason) {
      recognition = null
      dictating.value = false
      actionNotice.value = reason instanceof Error ? `Could not start speech-to-text: ${reason.message}` : 'Could not start speech-to-text.'
    }
  }

  function cancelDictation () {
    recognition?.abort()
    recognition = null
    dictating.value = false
    actionNotice.value = 'Dictation stopped. Any recognized text remains editable.'
  }

  async function loadAttachment (attachment: { id: string, storagePath: string }) {
    const current = attachmentUrls.value[attachment.id]
    if (current) {
      URL.revokeObjectURL(current)
      delete attachmentUrls.value[attachment.id]
      return
    }
    const url = await workspace.getMessageAttachmentUrl(attachment.storagePath)
    if (url) attachmentUrls.value[attachment.id] = url
    else actionNotice.value = workspace.backendError || 'Could not open the private attachment.'
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
    observeVisibleMessages()
  }

  function toggleMessageSelection (messageId: string) {
    selectedMessageIds.value = selectedMessageIds.value.includes(messageId)
      ? selectedMessageIds.value.filter(id => id !== messageId)
      : [...selectedMessageIds.value, messageId]
    openMenuMessageId.value = ''
  }

  function handleMessageClick (messageId: string) {
    if (suppressNextMessageClick === messageId) {
      suppressNextMessageClick = ''
      return
    }
    if (selectedMessageIds.value.length) toggleMessageSelection(messageId)
  }

  function startMessagePress (messageId: string, event: PointerEvent) {
    if (event.pointerType !== 'touch' || (event.target as HTMLElement).closest('button, form, a')) return
    pressOrigin = { x: event.clientX, y: event.clientY }
    longPressTimer = setTimeout(() => {
      toggleMessageSelection(messageId)
      suppressNextMessageClick = messageId
      pressOrigin = undefined
    }, 500)
  }

  function moveMessagePress (event: PointerEvent) {
    if (!pressOrigin) return
    const deltaX = event.clientX - pressOrigin.x
    const deltaY = event.clientY - pressOrigin.y
    if (deltaX > 58 && Math.abs(deltaY) < 36) {
      const element = (event.currentTarget as HTMLElement)
      const message = selectedConversation.value?.messages.find(item => item.id === element.dataset.messageId)
      if (message && !message.deletedAt) {
        setReplyTarget(message)
        suppressNextMessageClick = message.id
      }
      cancelMessagePress()
      return
    }
    if (Math.abs(deltaX) > 10 || Math.abs(deltaY) > 10) cancelMessagePress()
  }

  function cancelMessagePress () {
    if (longPressTimer) clearTimeout(longPressTimer)
    longPressTimer = undefined
    pressOrigin = undefined
  }

  function setReplyTarget (message: { id: string, author: string, text: string, deletedAt: string | null }) {
    if (message.deletedAt) return
    replyingTo.value = { id: message.id, author: message.author, text: message.text }
    openMenuMessageId.value = ''
    nextTick(() => document.querySelector<HTMLInputElement>('.composer input')?.focus())
  }

  function jumpToReply (messageId: string) {
    navigateToMessage(messageId)
  }

  async function toggleReaction (messageId: string, emoji: string) {
    const success = await workspace.toggleMessageReaction(messageId, emoji)
    if (!success && workspace.backendError) actionNotice.value = workspace.backendError
  }

  function onGlobalKeydown (event: KeyboardEvent) {
    if (event.key === 'Escape') {
      if (openMenuMessageId.value) openMenuMessageId.value = ''
      else selectedMessageIds.value = []
    }
    if (openMenuMessageId.value && ['ArrowDown', 'ArrowUp'].includes(event.key)) {
      const items = [...document.querySelectorAll<HTMLButtonElement>('[role="menu"] button:not(:disabled)')]
      const index = items.indexOf(document.activeElement as HTMLButtonElement)
      if (items.length) {
        event.preventDefault()
        items[(index + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus()
      }
    }
  }

  if (typeof window !== 'undefined') window.addEventListener('keydown', onGlobalKeydown)

  async function copyMessage (message: { text: string, deletedAt: string | null }) {
    if (message.deletedAt) return
    try {
      if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(message.text)
      else {
        const field = document.createElement('textarea')
        field.value = message.text
        field.setAttribute('readonly', '')
        field.style.position = 'fixed'
        field.style.opacity = '0'
        document.body.append(field)
        field.select()
        const copied = document.execCommand('copy')
        field.remove()
        if (!copied) throw new Error('Clipboard copy is unavailable in this browser.')
      }
      actionNotice.value = 'Message copied.'
    } catch {
      actionNotice.value = 'Could not copy this message. Check clipboard permissions and try again.'
    }
    openMenuMessageId.value = ''
    window.setTimeout(() => { actionNotice.value = '' }, 3000)
  }

  async function hideSelectedMessages () {
    const ids = [...selectedMessageIds.value]
    for (const id of ids) {
      if (!await workspace.hideMessageForMe(id)) {
        actionNotice.value = workspace.backendError || 'Some selected messages could not be hidden.'
        return
      }
    }
    selectedMessageIds.value = []
    actionNotice.value = ids.length === 1 ? 'Message deleted for you.' : `${ids.length} messages deleted for you.`
    window.setTimeout(() => { actionNotice.value = '' }, 3000)
  }

  async function deleteSelectedForEveryone () {
    const messages = selectedMessageIds.value.map(id => selectedConversation.value?.messages.find(message => message.id === id)).filter((message): message is NonNullable<typeof message> => Boolean(message))
    if (!messages.length || !messages.every(canDeleteForEveryone)) return
    if (!window.confirm(`Delete ${messages.length === 1 ? 'this message' : `these ${messages.length} messages`} for everyone?`)) return
    for (const message of messages) {
      if (!await workspace.deleteMessageForEveryone(message.id)) {
        actionNotice.value = workspace.backendError || 'Some messages could not be deleted.'
        return
      }
    }
    selectedMessageIds.value = []
  }

  function navigateToMessage (messageId: string) {
    const elements = messageList.value?.querySelectorAll<HTMLElement>('[data-message-id]') ?? []
    const element = [...elements].find(item => item.dataset.messageId === messageId)
    element?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    activeSearchMessageId.value = messageId
    window.setTimeout(() => { activeSearchMessageId.value = '' }, 1800)
  }

  function moveSearchResult (direction: number) {
    if (!messageSearchResults.value.length) return
    searchResultIndex.value = (searchResultIndex.value + direction + messageSearchResults.value.length) % messageSearchResults.value.length
    const result = messageSearchResults.value[searchResultIndex.value]
    if (result) navigateToMessage(result.id)
  }

  function messageTextParts (text: string) {
    const term = messageSearch.value.trim()
    if (!term) return [{ text, match: false }]
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    return text.split(new RegExp(`(${escaped})`, 'ig')).filter(Boolean).map(part => ({ text: part, match: part.toLocaleLowerCase() === term.toLocaleLowerCase() }))
  }

  function canEditMessage (message: { mine: boolean, createdAt: string, deletedAt: string | null }) {
    return message.mine && !message.deletedAt && Date.now() < Date.parse(message.createdAt) + 24 * 60 * 60 * 1000
  }

  function canDeleteForEveryone (message: { mine: boolean, createdAt: string, deletedAt: string | null }) {
    return message.mine && !message.deletedAt && Date.now() < Date.parse(message.createdAt) + 72 * 60 * 60 * 1000
  }

  function beginEdit (message: { id: string, text: string }) {
    editingMessageId.value = message.id
    editDraft.value = message.text
  }

  async function saveEdit (messageId: string) {
    if (!editDraft.value.trim()) return
    if (await workspace.editMessage(messageId, editDraft.value)) editingMessageId.value = ''
  }

  async function deleteForEveryone (messageId: string) {
    if (window.confirm('Delete this message for everyone? Its content will be replaced with a deletion notice.')) {
      await workspace.deleteMessageForEveryone(messageId)
    }
  }

  async function hideForMe (messageId: string) {
    await workspace.hideMessageForMe(messageId)
  }
</script>

<template>
  <main>
    <header class="page-heading"><div><p class="eyebrow">YOUR INBOX</p><h1>Messages</h1><p>Keep conversations moving with direct, thoughtful communication.</p></div><router-link class="secondary-action" to="/employees"><v-icon icon="mdi-plus" size="17" /> New message</router-link></header>
    <p v-if="workspace.backendError" class="message-error" role="alert">{{ workspace.backendError }}</p>

    <section class="messaging-layout surface-card" :class="{ 'has-selected-conversation': Boolean(selectedConversation || composingEmployee) }">
      <aside class="conversation-sidebar">
        <div class="inbox-heading"><strong>{{ showArchived ? 'Archived' : 'Inbox' }}</strong><span>{{ filteredConversations.length }}</span><button class="refresh-button" type="button" :aria-label="showArchived ? 'Show inbox' : 'Show archived conversations'" :title="showArchived ? 'Show inbox' : 'Show archived conversations'" @click="showArchived = !showArchived"><v-icon :icon="showArchived ? 'mdi-inbox' : 'mdi-archive-outline'" size="17" /></button><button class="refresh-button" type="button" aria-label="Refresh messages" title="Refresh messages" :disabled="refreshing" @click="refreshMessages"><v-icon icon="mdi-refresh" :class="{ spinning: refreshing }" size="17" /></button></div>
        <p v-if="refreshError" class="refresh-error" role="alert">{{ refreshError }}</p>
        <p v-else-if="workspace.messageSyncError" class="refresh-error" role="alert">{{ workspace.messageSyncError }}</p>
        <p v-if="workspace.receiptError" class="refresh-error" role="alert">{{ workspace.receiptError }}</p>
        <p v-if="workspace.presenceError" class="refresh-error" role="alert">{{ workspace.presenceError }}</p>
        <p v-if="workspace.interactionError" class="refresh-error" role="alert">{{ workspace.interactionError }}</p>
        <p v-if="workspace.conversationStateError" class="refresh-error" role="alert">{{ workspace.conversationStateError }}</p>
        <p v-if="workspace.typingError" class="refresh-error" role="alert">{{ workspace.typingError }}</p>
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
          <span><strong>{{ displayEmployee?.firstName }} {{ displayEmployee?.lastName }}</strong><small>{{ selectedConversation?.online ? 'Online' : selectedConversation?.lastSeenAt ? `Last seen ${new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(selectedConversation.lastSeenAt))}` : selectedConversation?.title || composingEmployee?.title || 'New message' }}</small></span>
          <button v-if="selectedConversation" class="chat-tool-button" type="button" :aria-label="selectedConversation.archived ? 'Restore conversation' : 'Archive conversation'" :title="selectedConversation.archived ? 'Restore conversation' : 'Archive conversation'" @click="workspace.setConversationState(selectedConversation.id, selectedConversation.archived ? 'restore' : 'archive')"><v-icon :icon="selectedConversation.archived ? 'mdi-inbox-arrow-down-outline' : 'mdi-archive-outline'" size="19" /></button>
          <button v-if="selectedConversation" class="chat-tool-button" type="button" aria-label="Mark conversation unread" title="Mark unread" @click="markCurrentConversationUnread"><v-icon icon="mdi-email-mark-as-unread" size="19" /></button>
          <div v-if="selectedConversation" class="chat-call-actions" role="group" aria-label="Call this employee">
            <button class="chat-tool-button" type="button" aria-label="Start voice call" :title="calls.signalingReady ? 'Start voice call' : 'Call signaling is connecting or unavailable'" :disabled="Boolean(!calls.signalingReady || calls.callStartInFlight || calls.activeCall || calls.incomingCall)" @click="startConversationCall('audio')"><v-icon icon="mdi-phone-outline" size="19" /></button>
            <button class="chat-tool-button" type="button" aria-label="Start video call" :title="calls.signalingReady ? 'Start video call' : 'Call signaling is connecting or unavailable'" :disabled="Boolean(!calls.signalingReady || calls.callStartInFlight || calls.activeCall || calls.incomingCall)" @click="startConversationCall('video')"><v-icon icon="mdi-video-outline" size="19" /></button>
          </div>
          <button class="chat-tool-button" type="button" :aria-expanded="messageSearchOpen" aria-label="Search in conversation" @click="messageSearchOpen = !messageSearchOpen; messageSearch = ''"><v-icon icon="mdi-magnify" size="19" /></button>
          <a v-if="displayEmployee?.email" class="chat-email" :href="`mailto:${displayEmployee.email}`" aria-label="Email colleague"><v-icon icon="mdi-email-outline" size="19" /></a>
        </header>

        <div v-if="selectedMessageIds.length" class="selection-toolbar" role="toolbar" aria-label="Selected message actions">
          <button type="button" aria-label="Cancel selection" title="Cancel selection" @click="selectedMessageIds = []"><v-icon icon="mdi-close" size="19" /></button>
          <strong>{{ selectedMessageIds.length }} selected</strong>
          <button type="button" aria-label="Delete selected messages for me" title="Delete for me" @click="hideSelectedMessages"><v-icon icon="mdi-delete-outline" size="19" /></button>
          <button v-if="selectedMessageIds.every(id => { const message = selectedConversation?.messages.find(item => item.id === id); return message && canDeleteForEveryone(message) })" type="button" aria-label="Delete selected messages for everyone" title="Delete for everyone" @click="deleteSelectedForEveryone"><v-icon icon="mdi-delete-forever-outline" size="19" /></button>
        </div>

        <div v-if="messageSearchOpen" class="message-search-panel">
          <input v-model="messageSearch" aria-label="Search messages in this conversation" autofocus placeholder="Search this conversation">
          <span>{{ messageSearchResults.length ? `${searchResultIndex + 1} of ${messageSearchResults.length}` : '0 results' }}</span>
          <button type="button" aria-label="Previous search result" :disabled="!messageSearchResults.length" @click="moveSearchResult(-1)"><v-icon icon="mdi-chevron-up" size="17" /></button>
          <button type="button" aria-label="Next search result" :disabled="!messageSearchResults.length" @click="moveSearchResult(1)"><v-icon icon="mdi-chevron-down" size="17" /></button>
          <button type="button" aria-label="Close search" @click="messageSearchOpen = false; messageSearch = ''"><v-icon icon="mdi-close" size="17" /></button>
          <div v-if="messageSearch.trim() && !messageSearchResults.length" class="search-empty">No messages match this search.</div>
          <button v-for="(result, index) in messageSearchResults" :key="result.id" class="search-result" type="button" @click="searchResultIndex = index; navigateToMessage(result.id)">
            <strong>{{ result.author }}</strong><span>{{ result.text }}</span><time>{{ result.sentAt }}</time>
          </button>
        </div>
        <p v-if="actionNotice" class="action-notice" role="status" aria-live="polite">{{ actionNotice }}</p>

        <div v-if="pinnedMessages.length" class="pinned-messages" aria-label="Messages pinned for you">
          <span><v-icon icon="mdi-pin" size="15" /> Pinned for you</span>
          <div v-for="message in pinnedMessages" :key="message.id" class="pinned-entry"><button type="button" @click="navigateToMessage(message.id)"><span>{{ message.author }}: {{ message.deletedAt ? 'This message was deleted' : message.text }}</span></button><button type="button" :aria-label="`Unpin message from ${message.author}`" @click="togglePinnedMessage(message.id)"><v-icon icon="mdi-close" size="15" /></button></div>
        </div>
        <p v-if="typingLabel" class="typing-indicator" role="status" aria-live="polite">{{ typingLabel }}</p>

        <div ref="messageList" class="message-list" @scroll="trackMessageScroll">
          <div class="conversation-date">TODAY</div>
          <p v-if="workspace.callHistoryError" class="call-history-error" role="status">{{ workspace.callHistoryError }}</p>

          <p v-if="composingEmployee && !selectedConversation" class="first-message-hint">This is a temporary message draft. A conversation is created only when your first message is sent.</p>

          <template v-for="message in selectedConversation?.messages ?? []" :key="message.id">
          <article v-if="message.callEvent" class="call-history-card" :class="{ mine: message.mine }" aria-label="Call history">
            <v-icon :icon="message.callEvent.callType === 'video' ? 'mdi-video-outline' : 'mdi-phone-outline'" size="18" />
            <div><strong>{{ message.text }}</strong><small v-if="message.callEvent.durationSeconds !== null" class="call-duration">{{ formatCallDuration(message.callEvent.durationSeconds) }}</small><time>{{ message.sentAt }}</time></div>
          </article>
          <article v-else :data-message-id="message.id" :data-message-version="message.contentVersion" class="chat-message" :class="{ mine: message.mine, deleted: Boolean(message.deletedAt), selected: selectedMessageIds.includes(message.id), 'search-highlight': activeSearchMessageId === message.id, 'has-menu': openMenuMessageId === message.id }" @click="handleMessageClick(message.id)" @pointerdown="startMessagePress(message.id, $event)" @pointermove="moveMessagePress" @pointerup="cancelMessagePress" @pointercancel="cancelMessagePress">
            <small v-if="!message.mine">{{ message.author }}</small>
            <button v-if="message.replyTo" class="reply-preview" type="button" @click.stop="jumpToReply(message.replyTo.id)"><strong>{{ message.replyTo.author }}</strong><span>{{ message.replyTo.text }}</span></button>
            <form v-if="editingMessageId === message.id" class="message-edit-form" @submit.prevent="saveEdit(message.id)">
              <textarea v-model="editDraft" aria-label="Edit message" rows="3" maxlength="10000" />
              <button type="submit" :disabled="!editDraft.trim()">Save edit</button>
              <button type="button" @click="editingMessageId = ''">Cancel</button>
            </form>
            <p v-else><template v-for="(part, index) in messageTextParts(message.text)" :key="`${message.id}-${index}`"><mark v-if="part.match">{{ part.text }}</mark><template v-else>{{ part.text }}</template></template></p>
            <div v-for="attachment in message.attachments" :key="attachment.id" class="message-attachment">
              <img v-if="attachment.mimeType.startsWith('image/') && attachmentUrls[attachment.id]" :src="attachmentUrls[attachment.id]" :alt="attachment.fileName" loading="lazy">
              <video v-else-if="attachment.mimeType.startsWith('video/') && attachmentUrls[attachment.id]" :src="attachmentUrls[attachment.id]" controls playsinline preload="metadata" :aria-label="attachment.fileName" />
              <audio v-else-if="attachment.mimeType.startsWith('audio/') && attachmentUrls[attachment.id]" :src="attachmentUrls[attachment.id]" controls preload="metadata" :aria-label="attachment.fileName" />
              <a v-else-if="attachmentUrls[attachment.id]" :href="attachmentUrls[attachment.id]" target="_blank" rel="noopener noreferrer">Open {{ attachment.fileName }}</a>
              <button v-else type="button" class="attachment-open" @click.stop="loadAttachment(attachment)">{{ attachment.mimeType.startsWith('audio/') ? 'Play voice message' : attachment.mimeType.startsWith('image/') || attachment.mimeType.startsWith('video/') ? 'Preview' : 'Open private file' }}</button>
              <small>{{ attachment.fileName }} · {{ formatBytes(attachment.sizeBytes) }}<template v-if="attachment.durationSeconds"> · {{ formatDuration(attachment.durationSeconds) }}</template></small>
              <button v-if="attachmentUrls[attachment.id]" type="button" class="attachment-refresh" @click.stop="loadAttachment(attachment)">Refresh private link</button>
            </div>
            <div class="message-footer"><time>{{ message.sentAt }}<span v-if="message.editedAt && !message.deletedAt"> · Edited</span></time>
              <span v-if="message.mine && !message.deletedAt" class="message-receipt" :class="{ read: message.recipientCount > 0 && message.readCount === message.recipientCount, delivered: message.recipientCount > 0 && message.deliveryCount === message.recipientCount && message.readCount < message.recipientCount }" :aria-label="message.readCount === message.recipientCount && message.recipientCount > 0 ? 'Read by all recipients' : message.deliveryCount === message.recipientCount && message.recipientCount > 0 ? 'Delivered to all recipients' : 'Saved'" :title="message.recipientCount ? `${message.readCount} read · ${message.deliveryCount} delivered of ${message.recipientCount}` : 'Saved'">
                <v-icon v-if="message.recipientCount > 0 && message.deliveryCount === message.recipientCount" icon="mdi-check-all" size="15" />
                <v-icon v-else icon="mdi-check" size="15" />
              </span>
            </div>
            <div v-if="!message.deletedAt" class="reaction-row" aria-label="Message reactions">
              <button v-for="reaction in reactionOptions" :key="reaction" class="reaction-button" :class="{ active: message.reactions.some(item => item.emoji === reaction && item.reactedByMe) }" type="button" :aria-label="`${reaction} reaction${message.reactions.find(item => item.emoji === reaction)?.count ? `, ${message.reactions.find(item => item.emoji === reaction)?.count} total` : ''}`" :aria-pressed="message.reactions.some(item => item.emoji === reaction && item.reactedByMe)" @click.stop="toggleReaction(message.id, reaction)"><span>{{ reaction }}</span><small v-if="message.reactions.find(item => item.emoji === reaction)">{{ message.reactions.find(item => item.emoji === reaction)?.count }}</small></button>
            </div>
            <button class="message-menu-trigger" type="button" :aria-label="`Actions for message from ${message.author}`" :aria-expanded="openMenuMessageId === message.id" aria-haspopup="menu" @click.stop="openMenuMessageId = openMenuMessageId === message.id ? '' : message.id"><v-icon icon="mdi-dots-vertical" size="18" /></button>
            <div v-if="openMenuMessageId === message.id" class="message-context-menu" role="menu" @click.stop>
              <button v-if="!message.deletedAt" role="menuitem" type="button" @click="copyMessage(message)"><v-icon icon="mdi-content-copy" size="16" /> Copy text</button>
              <button v-if="!message.deletedAt" role="menuitem" type="button" @click="setReplyTarget(message)"><v-icon icon="mdi-reply-outline" size="16" /> Reply</button>
              <button v-if="!message.deletedAt" role="menuitem" type="button" @click="togglePinnedMessage(message.id)"><v-icon :icon="selectedConversation?.pinnedMessageIds.includes(message.id) ? 'mdi-pin-off-outline' : 'mdi-pin-outline'" size="16" /> {{ selectedConversation?.pinnedMessageIds.includes(message.id) ? 'Unpin for me' : 'Pin for me' }}</button>
              <button role="menuitem" type="button" @click="toggleMessageSelection(message.id)"><v-icon icon="mdi-checkbox-multiple-outline" size="16" /> Select message</button>
              <button v-if="message.mine && canEditMessage(message)" role="menuitem" type="button" @click="beginEdit(message); openMenuMessageId = ''"><v-icon icon="mdi-pencil-outline" size="16" /> Edit</button>
              <button v-if="message.mine && canDeleteForEveryone(message)" role="menuitem" type="button" @click="deleteForEveryone(message.id); openMenuMessageId = ''"><v-icon icon="mdi-delete-forever-outline" size="16" /> Delete for everyone</button>
              <button role="menuitem" type="button" @click="hideForMe(message.id); openMenuMessageId = ''"><v-icon icon="mdi-delete-outline" size="16" /> Delete for me</button>
            </div>
          </article>
          </template>
        </div>

        <form class="composer" @submit.prevent="send">
          <div v-if="replyingTo" class="composer-reply"><div><strong>Replying to {{ replyingTo.author }}</strong><span>{{ replyingTo.text }}</span></div><button type="button" aria-label="Cancel reply" @click="replyingTo = null"><v-icon icon="mdi-close" size="17" /></button></div>
          <div v-if="selectedAttachment" class="upload-selection"><span>{{ selectedAttachment.name }} · {{ formatBytes(selectedAttachment.size) }}</span><button v-if="!uploadingAttachment" type="button" aria-label="Remove selected attachment" @click="selectedAttachment = null"><v-icon icon="mdi-close" size="16" /></button></div>
          <div v-if="recordedVoiceUrl" class="voice-preview"><audio :src="recordedVoiceUrl" controls preload="metadata" aria-label="Voice recording preview" /><span>{{ formatDuration(recordingSeconds) }}</span><button type="button" aria-label="Discard voice recording" @click="stopVoiceRecording(true)"><v-icon icon="mdi-delete-outline" size="17" /></button></div>
          <div v-if="uploadingAttachment" class="upload-progress" role="progressbar" :aria-valuenow="uploadProgress" aria-valuemin="0" aria-valuemax="100" :aria-label="`Uploading attachment ${uploadProgress}%`"><span :style="{ width: `${uploadProgress}%` }" /><small>{{ uploadProgress }}% uploaded</small><button type="button" @click="cancelAttachmentUpload">Cancel upload</button></div>
          <div v-if="recordingVoice" class="recording-state" role="group" aria-label="Voice recording controls"><span class="recording-indicator" :class="{ paused: recordingPaused }" /><span>{{ recordingPaused ? 'Paused' : 'Recording' }} {{ formatDuration(recordingSeconds) }}</span><div class="recording-actions"><button type="button" :aria-label="recordingPaused ? 'Resume recording' : 'Pause recording'" :title="recordingPaused ? 'Resume recording' : 'Pause recording'" @click="toggleVoiceRecordingPause"><v-icon :icon="recordingPaused ? 'mdi-play' : 'mdi-pause'" size="17" /></button><button type="button" aria-label="Cancel recording" title="Cancel recording" @click="stopVoiceRecording(true)"><v-icon icon="mdi-delete-outline" size="17" /></button><button type="button" aria-label="Finish recording" title="Finish recording" @click="stopVoiceRecording(false)"><v-icon icon="mdi-check" size="17" /></button></div></div>
          <input ref="attachmentInput" class="attachment-input" type="file" accept="image/jpeg,image/png,image/gif,image/webp,video/mp4,video/webm,application/pdf,text/plain,text/csv,.doc,.docx,.xls,.xlsx,.ppt,.pptx" aria-label="Choose an attachment" @change="chooseAttachment">
          <button v-if="!recordingVoice && !recordedVoiceFile && !selectedAttachment" type="button" class="composer-tool" aria-label="Attach image, video or document" title="Attach file" :disabled="uploadingAttachment" @click="attachmentInput?.click()"><v-icon icon="mdi-paperclip" size="19" /></button>
          <button v-if="!recordingVoice && !recordedVoiceFile && !selectedAttachment" type="button" class="composer-tool" aria-label="Record voice message" title="Record voice message" :disabled="uploadingAttachment" @click="startVoiceRecording"><v-icon icon="mdi-microphone-outline" size="19" /></button>
          <button v-if="!recordingVoice && !recordedVoiceFile && !selectedAttachment" type="button" class="composer-tool" :class="{ 'dictation-active': dictating }" :aria-label="dictating ? 'Stop speech-to-text' : 'Dictate message text'" :title="dictating ? 'Stop dictation' : 'Dictate message text'" :disabled="uploadingAttachment" @click="toggleDictation"><v-icon :icon="dictating ? 'mdi-stop' : 'mdi-microphone-message'" size="19" /></button>
          <button v-if="dictating" type="button" class="composer-tool" aria-label="Cancel speech-to-text" title="Cancel dictation" @click="cancelDictation"><v-icon icon="mdi-close" size="18" /></button>
          <input v-model="draft" aria-label="Write a message" autocomplete="off" placeholder="Write a message..." @input="handleComposerInput" @blur="selectedConversation && workspace.updateConversationTyping(selectedConversation.id, false)">
          <button v-if="recordedVoiceFile" type="button" aria-label="Send voice message" :disabled="uploadingAttachment" @click="uploadChatFile(recordedVoiceFile, recordingSeconds)"><v-icon icon="mdi-send" size="18" /></button>
          <button v-else-if="selectedAttachment" type="button" aria-label="Upload attachment" :disabled="uploadingAttachment" @click="uploadChatFile(selectedAttachment)"><v-icon icon="mdi-send" size="18" /></button>
          <button v-else aria-label="Send message" :disabled="!draft.trim() || sending || uploadingAttachment" type="submit"><v-icon icon="mdi-send" size="18" /></button>
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
.pinned-messages { display: grid; gap: 5px; border-bottom: 1px solid var(--ns-border-e7ebe3, #e7ebe3); padding: 8px 13px; background: var(--ns-bg-f5f7f1, #f5f7f1); }
.pinned-messages > span { display: flex; align-items: center; gap: 5px; color: var(--ns-text-secondary); font-size: 9px; }
.pinned-entry { display: flex; min-width: 0; align-items: center; gap: 5px; }
.pinned-entry button { min-width: 0; border: 0; border-radius: 5px; padding: 5px; background: transparent; color: var(--ns-text-18352d, #18352d); cursor: pointer; font: inherit; font-size: 10px; text-align: left; }
.pinned-entry button:first-child { flex: 1; }
.pinned-entry button:first-child span { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.typing-indicator { margin: 0; padding: 5px 14px; color: var(--ns-text-secondary); font-size: 10px; font-style: italic; }
.chat-panel { display: flex; min-width: 0; flex-direction: column; }
.chat-header { display: flex; min-height: 69px; align-items: center; gap: 11px; padding: 12px 18px; border-bottom: 1px solid var(--ns-border-e7ebe3, #e7ebe3); }
.chat-tool-button, .message-search-panel > button, .selection-toolbar button { display: grid; width: 34px; height: 34px; flex: 0 0 auto; place-items: center; border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 9px; background: var(--ns-surface, #fff); color: var(--ns-text-18352d, #18352d); cursor: pointer; }
.chat-tool-button { margin-left: auto; }
.chat-call-actions { display: flex; flex: 0 0 auto; gap: 6px; margin-left: auto; }
.chat-call-actions .chat-tool-button { margin-left: 0; }
.chat-call-actions .chat-tool-button:disabled { cursor: not-allowed; opacity: .48; }
.chat-tool-button:focus-visible, .selection-toolbar button:focus-visible, .message-search-panel button:focus-visible, .message-context-menu button:focus-visible, .message-menu-trigger:focus-visible { outline: 2px solid var(--ns-blue-primary, #2563eb); outline-offset: 2px; }
.conversation-back { display: inline-flex; min-height: 36px; align-items: center; gap: 5px; border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 8px; padding: 0 9px; background: transparent; color: var(--ns-text-18352d, #18352d); cursor: pointer; font: inherit; font-size: 10px; }
.conversation-back:hover { background: var(--ns-bg-f1f4eb, #f1f4eb); }
.conversation-back:focus-visible { outline: 2px solid var(--ns-blue-primary, #2563eb); outline-offset: 2px; }
.chat-header > span:nth-child(2) { display: grid; gap: 4px; }
.chat-header strong { color: var(--ns-text-18352d, #18352d); font-size: 11px; }
.chat-header small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.conversation-avatar.large { flex-basis: 38px; width: 38px; height: 38px; }
.chat-email { margin-left: auto; color: var(--ns-text-71897b, #71897b); }
.chat-email + .chat-tool-button { margin-left: 0; }
.selection-toolbar { position: sticky; z-index: 5; top: 0; display: flex; min-height: 48px; align-items: center; gap: 10px; border-bottom: 1px solid var(--ns-border-e7ebe3, #e7ebe3); padding: 6px 12px; background: var(--ns-surface, #fff); color: var(--ns-text-18352d, #18352d); }
.selection-toolbar strong { margin-right: auto; font-size: 12px; }
.message-search-panel { display: flex; flex-wrap: wrap; align-items: center; gap: 7px; border-bottom: 1px solid var(--ns-border-e7ebe3, #e7ebe3); padding: 9px 12px; background: var(--ns-surface, #fff); }
.message-search-panel input { min-width: 130px; flex: 1; border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 8px; padding: 8px 10px; background: var(--ns-surface, #fff); color: var(--ns-text-18352d, #18352d); font: inherit; font-size: 11px; }
.message-search-panel > span { color: var(--ns-text-secondary); font-size: 10px; white-space: nowrap; }
.message-search-panel button:disabled { cursor: not-allowed; opacity: .45; }
.search-empty { flex-basis: 100%; padding: 10px; color: var(--ns-text-secondary); font-size: 11px; }
.search-result { display: grid; flex-basis: 100%; gap: 3px; border: 0; border-radius: 7px; padding: 7px 9px; background: var(--ns-bg-f5f7f1, #f5f7f1); color: var(--ns-text-18352d, #18352d); cursor: pointer; text-align: left; }
.search-result strong, .search-result time { color: var(--ns-text-secondary); font-size: 9px; }
.search-result span { overflow: hidden; font-size: 10px; text-overflow: ellipsis; white-space: nowrap; }
.action-notice { margin: 0; border-bottom: 1px solid var(--ns-border-e7ebe3, #e7ebe3); padding: 8px 13px; color: var(--ns-text-secondary); font-size: 10px; }
.message-list { display: flex; flex: 1; flex-direction: column; gap: 15px; overflow-y: auto; padding: 22px; }
.call-history-error { align-self: center; color: var(--ns-text-secondary); font-size: 10px; }
.call-history-card { display: flex; max-width: min(84%, 360px); min-height: 54px; align-items: center; gap: 10px; align-self: center; border: 1px solid var(--ns-border-e3e9dc, #e3e9dc); border-radius: 12px; padding: 9px 13px; background: var(--ns-surface, #fff); color: var(--ns-text-secondary, #64756b); }
.call-history-card div { display: grid; gap: 4px; }
.call-history-card strong { color: var(--ns-text-primary, #18352d); font-size: 10px; font-weight: 600; }
.call-history-card .call-duration { color: var(--ns-text-secondary, #64756b); font-size: 10px; line-height: 1.3; }
.call-history-card time { color: var(--ns-text-a1aaa2, #a1aaa2); font-size: 8px; }
.conversation-date { align-self: center; color: var(--ns-text-a1aaa2, #a1aaa2); font: 8px "DM Mono", monospace; letter-spacing: 1px; }
.first-message-hint { align-self: center; max-width: 360px; color: var(--ns-text-secondary); font-size: 11px; line-height: 1.6; text-align: center; }
.chat-message { position: relative; max-width: min(78%, 430px); align-self: flex-start; border-radius: 8px; touch-action: pan-y; }
.chat-message.selected { outline: 2px solid var(--ns-blue-primary, #2563eb); outline-offset: 4px; background: color-mix(in srgb, var(--ns-blue-primary, #2563eb) 8%, transparent); }
.chat-message.search-highlight { animation: message-flash 1.8s ease-out; }
@keyframes message-flash { 0%, 30% { outline: 3px solid var(--ns-blue-primary, #2563eb); outline-offset: 4px; } 100% { outline: 3px solid transparent; outline-offset: 8px; } }
.chat-message.mine { align-self: flex-end; text-align: right; }
.chat-message > small { color: var(--ns-text-829187, #829187); font-size: 9px; }
.chat-message p { margin: 5px 0 4px; border: 1px solid var(--ns-border-e3e9dc, #e3e9dc); padding: 10px 13px; background: var(--ns-bg-f5f7f1, #f5f7f1); color: var(--ns-text-394d41, #394d41); text-align: left; font-size: 10px; line-height: 1.6; }
.chat-message.mine p { border-color: var(--ns-border-18352d, #18352d); background: var(--ns-bg-18352d, #18352d); color: var(--ns-text-f3f5ef, #f3f5ef); }
.reply-preview { display: grid; width: 100%; gap: 3px; border: 0; border-inline-start: 3px solid var(--ns-blue-primary, #2563eb); border-radius: 5px; padding: 7px 9px; background: color-mix(in srgb, var(--ns-blue-primary, #2563eb) 8%, var(--ns-surface, #fff)); color: var(--ns-text-18352d, #18352d); cursor: pointer; text-align: left; }
.reply-preview strong { font-size: 9px; }
.reply-preview span { overflow: hidden; color: var(--ns-text-secondary); font-size: 9px; text-overflow: ellipsis; white-space: nowrap; }
.chat-message.mine .reply-preview { color: var(--ns-text-18352d, #18352d); }
.message-attachment { display: grid; max-width: min(65vw, 360px); gap: 5px; margin-top: 6px; border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 9px; padding: 7px; background: var(--ns-surface, #fff); text-align: left; }
.message-attachment img, .message-attachment video { display: block; max-width: 100%; max-height: 280px; border-radius: 6px; object-fit: contain; }
.message-attachment audio { width: min(100%, 320px); }
.message-attachment small { overflow-wrap: anywhere; color: var(--ns-text-secondary); font-size: 9px; }
.attachment-open, .attachment-refresh { justify-self: start; border: 0; padding: 4px 0; background: transparent; color: var(--ns-blue-primary, #2563eb); cursor: pointer; font: inherit; font-size: 10px; }
.message-attachment a { color: var(--ns-blue-primary, #2563eb); font-size: 10px; }
.reaction-row { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 4px; margin-top: 4px; }
.reaction-button { display: inline-flex; min-width: 27px; min-height: 25px; align-items: center; justify-content: center; gap: 3px; border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 999px; padding: 2px 6px; background: var(--ns-surface, #fff); cursor: pointer; }
.reaction-button.active { border-color: var(--ns-blue-primary, #2563eb); background: color-mix(in srgb, var(--ns-blue-primary, #2563eb) 10%, white); }
.reaction-button span { font-size: 12px; line-height: 1; }
.reaction-button small { color: var(--ns-text-secondary); font-size: 9px; }
.reaction-button:focus-visible, .reply-preview:focus-visible, .composer-reply button:focus-visible { outline: 2px solid var(--ns-blue-primary, #2563eb); outline-offset: 2px; }
.chat-message time { color: var(--ns-text-a1aaa2, #a1aaa2); font-size: 8px; }
.chat-message.deleted p { border-style: dashed; background: transparent; color: var(--ns-text-829187, #829187); font-style: italic; }
.message-footer { display: flex; align-items: center; justify-content: flex-end; gap: 4px; }
.message-receipt { color: #8b948e; }
.message-receipt.delivered { color: #7b8580; }
.message-receipt.read { color: #2879cf; }
.message-actions { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 8px; margin-top: 5px; }
.message-actions button, .message-edit-form button { border: 0; padding: 2px 0; background: transparent; color: var(--ns-text-71897b, #71897b); cursor: pointer; font: inherit; font-size: 9px; }
.chat-message mark { border-radius: 2px; padding: 0 1px; background: #e8dc7a; color: #26342d; }
.message-menu-trigger { position: absolute; z-index: 2; top: 2px; inset-inline-end: 2px; display: grid; width: 30px; height: 30px; place-items: center; border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 50%; background: var(--ns-surface, #fff); color: var(--ns-text-18352d, #18352d); cursor: pointer; opacity: .95; }
.message-context-menu { position: absolute; z-index: 10; top: 32px; inset-inline-end: 0; display: grid; width: min(220px, calc(100vw - 30px)); border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 10px; padding: 5px; background: var(--ns-surface, #fff); box-shadow: 0 12px 28px rgb(19 41 32 / 18%); }
.message-context-menu button { display: flex; min-height: 38px; align-items: center; gap: 9px; border: 0; border-radius: 6px; padding: 0 9px; background: transparent; color: var(--ns-text-18352d, #18352d); cursor: pointer; font: inherit; font-size: 11px; text-align: left; }
.message-context-menu button:hover { background: var(--ns-bg-f1f4eb, #f1f4eb); }
.message-edit-form { display: grid; gap: 6px; min-width: min(70vw, 320px); border: 1px solid var(--ns-border); padding: 8px; }
.message-edit-form textarea { resize: vertical; border: 1px solid var(--ns-border); padding: 8px; font: inherit; }
.message-error { grid-column: 1 / -1; margin: 0; padding: 10px 15px; background: #fff2ef; color: var(--ns-danger-text, #9b3328); font-size: 11px; }
.composer { display: flex; flex-wrap: wrap; gap: 8px; margin: 0 17px 17px; border: 1px solid var(--ns-border-dce4d8, #dce4d8); padding: 6px; }
.attachment-input { display: none; }
.composer-tool { display: grid; width: 36px; height: 34px; flex: 0 0 auto; place-items: center; border: 1px solid var(--ns-border-e7ebe3, #e7ebe3); border-radius: 8px; background: var(--ns-surface, #fff); color: var(--ns-primary); cursor: pointer; }
.composer-tool:disabled { cursor: wait; opacity: .5; }
.composer-tool.dictation-active { border-color: var(--ns-blue-primary, #2563eb); background: var(--ns-blue-tint, #eff6ff); color: var(--ns-blue-primary, #2563eb); }
.upload-selection, .voice-preview, .upload-progress, .recording-state { display: flex; width: 100%; min-width: 0; align-items: center; gap: 9px; border-radius: 7px; padding: 7px 9px; background: var(--ns-bg-f5f7f1, #f5f7f1); color: var(--ns-text-18352d, #18352d); font-size: 10px; }
.upload-selection span { overflow: hidden; flex: 1; text-overflow: ellipsis; white-space: nowrap; }
.upload-selection button, .voice-preview button, .recording-state button, .upload-progress button { border: 0; background: transparent; color: var(--ns-text-18352d, #18352d); cursor: pointer; font: inherit; }
.voice-preview audio { min-width: 0; flex: 1; height: 34px; }
.voice-preview span { color: var(--ns-text-secondary); font-size: 9px; }
.recording-state { min-height: 48px; flex-wrap: wrap; }
.recording-indicator { width: 8px; height: 8px; flex: 0 0 auto; border-radius: 50%; background: #dc2626; animation: recording-pulse 1s ease-in-out infinite alternate; }
.recording-indicator.paused { background: #94a3b8; animation: none; }
.recording-actions { display: flex; gap: 5px; margin-left: auto; }
.recording-actions button { display: grid; width: 32px; height: 30px; place-items: center; border: 1px solid var(--ns-border); border-radius: 999px; background: var(--ns-surface); }
@keyframes recording-pulse { to { opacity: .35; } }
.upload-progress { position: relative; overflow: hidden; min-height: 32px; }
.upload-progress > span { position: absolute; inset: 0 auto 0 0; z-index: 0; background: color-mix(in srgb, var(--ns-blue-primary, #2563eb) 14%, transparent); transition: width .15s linear; }
.upload-progress small, .upload-progress button { position: relative; z-index: 1; }
.upload-progress button { margin-left: auto; }
.recording-state i { width: 9px; height: 9px; border-radius: 50%; background: #c83232; animation: recording-pulse 1s ease-in-out infinite alternate; }
@keyframes recording-pulse { to { opacity: .35; } }
.composer-reply { display: flex; width: 100%; align-items: center; justify-content: space-between; gap: 10px; border-inline-start: 3px solid var(--ns-blue-primary, #2563eb); padding: 6px 8px; background: var(--ns-bg-f5f7f1, #f5f7f1); }
.composer-reply > div { display: grid; min-width: 0; gap: 3px; }
.composer-reply strong { color: var(--ns-text-18352d, #18352d); font-size: 9px; }
.composer-reply span { overflow: hidden; color: var(--ns-text-secondary); font-size: 9px; text-overflow: ellipsis; white-space: nowrap; }
.composer-reply button { display: grid; width: 28px; height: 28px; flex: 0 0 auto; place-items: center; border: 0; border-radius: 50%; background: transparent; color: var(--ns-text-18352d, #18352d); cursor: pointer; }
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
  .chat-message { max-width: 88%; }
  .message-list { padding: 16px 12px; }
  .message-menu-trigger { top: -10px; inset-inline-end: -8px; }
}
@media (hover: hover) and (pointer: fine) {
  .message-menu-trigger { opacity: 0; transition: opacity .15s ease; }
  .chat-message:hover .message-menu-trigger, .chat-message:focus-within .message-menu-trigger { opacity: 1; }
}
</style>
