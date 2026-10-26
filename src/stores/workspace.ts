import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured, supabase, uploadPrivateMessageObject } from '../../lib/supabase.js'

const isUuid = (value: string | null | undefined): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)

const normalizeUuid = (value: unknown): string | null => {
  if (typeof value !== 'string') return null
  const normalized = value.trim().toLowerCase()
  return isUuid(normalized) ? normalized : null
}

const pendingAttachmentRequests = new Map<string, { requestId: string, path: string }>()

export type Employee = {
  id: string
  firstName: string
  lastName: string
  title: string
  department: string
  email: string
  phone: string
  online: boolean | null
  lastSeenAt: string | null
  initials: string
  color: string
  photoUrl?: string
}

export type Announcement = {
  id: string
  title: string
  description: string
  author: string
  department: string
  createdAt: string
  priority: 'High' | 'Normal' | 'Low'
  pinned: boolean
}

export type ChatMessage = {
  id: string
  author: string
  text: string
  sentAt: string
  createdAt: string
  mine: boolean
  editedAt: string | null
  deletedAt: string | null
  contentVersion: number
  deliveryCount: number
  readCount: number
  recipientCount: number
  replyTo: { id: string, author: string, text: string } | null
  reactions: { emoji: string, count: number, reactedByMe: boolean }[]
  attachments: MessageAttachment[]
  callEvent?: { callType: 'audio' | 'video', status: string, expiresAt: string, durationSeconds: number | null }
}

export type MessageAttachment = {
  id: string
  storagePath: string
  fileName: string
  mimeType: string
  sizeBytes: number
  durationSeconds: number | null
}

export type Conversation = {
  id: string
  employeeId: string
  name: string
  title: string
  initials: string
  color: string
  online: boolean | null
  lastSeenAt: string | null
  unread: number
  archived: boolean
  markedUnread: boolean
  pinnedMessageIds: string[]
  typingUserIds: string[]
  updatedAt: string
  messages: ChatMessage[]
}

export type WorkspaceNotification = {
  id: string
  title: string
  description: string
  category: 'Announcements' | 'Messages' | 'Events' | 'People'
  createdAt: string
  unread: boolean
  to: string
}

export type CompanyEvent = {
  id: string
  title: string
  startsAt: string
  endsAt: string | null
  location: string
  description: string
  organizer: string
  attendees: number
  attending: boolean
}

export type Resource = {
  id: string
  title: string
  category: string
  description: string
  format: string
  updatedAt: string
  fileUrl?: string
}

export const useWorkspaceStore = defineStore('workspace', () => {
  const employeeList = ref<Employee[]>([])
  const announcementList = ref<Announcement[]>([])
  const conversations = ref<Conversation[]>([])
  const notificationList = ref<WorkspaceNotification[]>([])
  const eventList = ref<CompanyEvent[]>([])
  const resourceList = ref<Resource[]>([])
  const departmentList = ref<{ id: string, name: string, description: string }[]>([])
  const activityLogs = ref<{ id: string, action: string, description: string, createdAt: string, user: string }[]>([])
  const backendError = ref('')
  const messageSyncError = ref('')
  const receiptError = ref('')
  const presenceError = ref('')
  const interactionError = ref('')
  const conversationStateError = ref('')
  const typingError = ref('')
  const messageToast = ref<{ title: string, preview: string, conversationId: string, notificationId: string } | null>(null)
  const loading = ref(false)
  let realtimeChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null
  let notificationChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null
  let notificationRefresh: { userId: string, promise: Promise<{ message: string } | null> } | null = null
  let notificationSubscriptionInterrupted = false
  let messageToastTimer: ReturnType<typeof setTimeout> | undefined
  let conversationRefreshPromise: Promise<string> | null = null
  let presenceHeartbeatTimer: ReturnType<typeof setInterval> | undefined
  let presenceVisibilityHandler: (() => void) | undefined
  let presenceHeartbeatInFlight = false
  let presenceRequestGeneration = 0
  let typingRefreshTimer: ReturnType<typeof setInterval> | undefined
  const lastTypingSentAt = new Map<string, number>()
  const pendingMessageRequests = new Map<string, string>()
  const callHistoryError = ref('')
  const unreadNotifications = computed(() => notificationList.value.filter(item => item.unread).length)

  function logSupabaseDiagnostic (label: string, error: unknown) {
    if (!import.meta.env.DEV) return
    const detail = error && typeof error === 'object'
      ? error as { code?: unknown, message?: unknown, details?: unknown, hint?: unknown, status?: unknown }
      : null
    console.error(`[Northstar ${label}]`, {
      code: detail?.code,
      message: detail?.message ?? (error instanceof Error ? error.message : String(error)),
      details: detail?.details,
      hint: detail?.hint,
      status: detail?.status,
    })
  }

  async function refreshNotifications (replace = false): Promise<{ message: string } | null> {
    const auth = useAuthStore()
    if (!isUuid(auth.userId) || !auth.canAccessEmployeeWorkspace || !isSupabaseConfigured || !supabase) return null
    const userId = auth.userId
    if (notificationRefresh?.userId === userId) return notificationRefresh.promise

    const notificationIdsAtStart = new Set(notificationList.value.map(item => item.id))
    const client = supabase
    const promise = (async (): Promise<{ message: string } | null> => {
      let notificationRows: Array<{
        id: string
        title: string
        message: string
        notification_type: string
        is_read: boolean
        created_at: string
        link_to?: string | null
      }> | null = null
      let notificationError: { message: string, code?: string } | null = null
      const notificationQuery = await client
        .from('notifications')
        .select('id,title,message,notification_type,is_read,created_at,link_to')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
      if (notificationQuery.error && isMissingNotificationLinkToColumn(notificationQuery.error)) {
        const fallbackQuery = await client
          .from('notifications')
          .select('id,title,message,notification_type,is_read,created_at')
          .eq('user_id', userId)
          .order('created_at', { ascending: false })
        notificationRows = fallbackQuery.data
        notificationError = fallbackQuery.error
      } else {
        notificationRows = notificationQuery.data
        notificationError = notificationQuery.error
      }

      if (useAuthStore().userId !== userId || !useAuthStore().canAccessEmployeeWorkspace) return null
      if (notificationError) return notificationError

      const loadedNotifications = (notificationRows ?? []).map(row => ({
        id: row.id,
        title: row.title,
        description: row.message,
        category: notificationCategory(row.notification_type),
        createdAt: new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(row.created_at)),
        unread: !row.is_read,
        to: notificationRoute(row.notification_type, row.title, row.link_to),
      }))
      if (replace) {
        const loadedIds = new Set(loadedNotifications.map(item => item.id))
        const arrivedDuringRefresh = notificationList.value.filter(item =>
          !notificationIdsAtStart.has(item.id) && !loadedIds.has(item.id),
        )
        notificationList.value = [...arrivedDuringRefresh, ...loadedNotifications]
      } else {
        const existingIds = new Set(notificationList.value.map(item => item.id))
        notificationList.value = [
          ...loadedNotifications.filter(item => !existingIds.has(item.id)),
          ...notificationList.value,
        ]
      }
      return null
    })()

    notificationRefresh = { userId, promise }
    try {
      return await promise
    } finally {
      if (notificationRefresh?.promise === promise) notificationRefresh = null
    }
  }

  const departments = computed(() => {
    return departmentList.value.map(department => ({
      name: department.name,
      count: employeeList.value.filter(employee => employee.department === department.name).length,
      description: department.description,
      members: employeeList.value.filter(employee => employee.department === department.name),
    }))
  })

  async function loadAnnouncements () {
    const auth = useAuthStore()
    if (!auth.isAuthenticated || (!auth.isAdmin && !auth.canAccessEmployeeWorkspace)) {
      announcementList.value = []
      return ''
    }
    if (!isSupabaseConfigured || !supabase) {
      return 'Loading announcements requires a configured Northstar Supabase connection.'
    }

    const { data, error } = await supabase
      .from('announcements')
      .select('id,title,content,author_id,department_id,priority,is_pinned,created_at,author:profiles!announcements_author_id_fkey(first_name,last_name),department:departments!announcements_department_id_fkey(name)')
      .order('is_pinned', { ascending: false })
      .order('created_at', { ascending: false })
    if (error) {
      return error.message
    }
    announcementList.value = (data ?? []).map(row => {
      const author = relationOne(row.author)
      const department = relationOne(row.department)
      return {
        id: row.id,
        title: row.title,
        description: row.content,
        author: `${author?.first_name ?? ''} ${author?.last_name ?? ''}`.trim() || (row.author_id ? 'Name unavailable' : 'Creator not recorded'),
        department: department?.name ?? 'Company',
        createdAt: row.created_at,
        priority: ({ normal: 'Normal', important: 'High', urgent: 'High' } as const)[row.priority as 'normal' | 'important' | 'urgent'] ?? 'Normal',
        pinned: row.is_pinned,
      }
    })
    return ''
  }

  async function load () {
    const auth = useAuthStore()
    if (!isUuid(auth.userId) || auth.isAdmin || !auth.canAccessEmployeeWorkspace) {
      clearWorkspace()
      return
    }
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Northstar Supabase is not configured. Add the project URL and public key to the local environment before loading workspace data.'
      return
    }
    const client = supabase
    if (loading.value) {
      return
    }

    loading.value = true
    backendError.value = ''
    receiptError.value = ''
    presenceError.value = ''
    interactionError.value = ''
    conversationStateError.value = ''
    typingError.value = ''
    employeeList.value = []
    announcementList.value = []
    conversations.value = []
    notificationList.value = []
    eventList.value = []
    resourceList.value = []
    departmentList.value = []
    activityLogs.value = []
    const errors: string[] = []
    const recordError = (section: string, error: { message: string }) => {
      errors.push(`${section}: ${error.message}`)
      console.error(`Supabase ${section} query failed`, error)
    }

    const { data: departmentRows, error: departmentError } = await supabase
      .from('departments')
      .select('id,name,description')
      .order('name')
    if (departmentError) {
      recordError('departments', departmentError)
    } else {
      departmentList.value = (departmentRows ?? []).map(row => ({ id: row.id, name: row.name, description: row.description ?? '' }))
    }

    const { data: employeeRows, error: employeeError } = await supabase
      .from('profiles')
      .select('id,first_name,last_name,email,avatar_url,job_title,department_id,employment_status,departments(name)')
      .eq('approval_status', 'approved')
      .eq('employment_status', 'active')
      .order('first_name')
    if (employeeError) {
      recordError('employee directory', employeeError)
    } else {
      employeeList.value = await Promise.all((employeeRows ?? []).map(async row => {
        const department = relationOne(row.departments)
        const firstName = row.first_name ?? ''
        const lastName = row.last_name ?? ''
        let photoUrl = ''
        if (row.avatar_url) {
          const { data: avatar, error: avatarError } = await client.storage
            .from('profile-avatars')
            .createSignedUrl(row.avatar_url, 3600)
          if (avatarError) {
            recordError(`profile photo for ${firstName}`, avatarError)
          } else {
            photoUrl = avatar.signedUrl
          }
        }
        return {
          id: row.id,
          firstName,
          lastName,
          title: row.job_title ?? '',
          department: department?.name ?? '',
          email: row.email ?? '',
          phone: '',
          online: null,
          lastSeenAt: null,
          initials: `${firstName[0] ?? ''}${lastName[0] ?? ''}`.toUpperCase(),
          color: avatarColors[(row.id.codePointAt(0) ?? 0) % avatarColors.length] ?? '#dce8ba',
          photoUrl,
        }
      }))
    }

    const { data: announcementRows, error: announcementError } = await supabase
      .from('announcements')
      .select('id,title,content,author_id,department_id,priority,is_pinned,created_at,author:profiles!announcements_author_id_fkey(first_name,last_name),department:departments!announcements_department_id_fkey(name)')
      .order('is_pinned', { ascending: false })
      .order('created_at', { ascending: false })
    if (announcementError) {
      recordError('announcements', announcementError)
    } else {
      announcementList.value = (announcementRows ?? []).map(row => {
        const author = relationOne(row.author)
        const department = relationOne(row.department)
        return {
          id: row.id,
          title: row.title,
          description: row.content,
          author: `${author?.first_name ?? ''} ${author?.last_name ?? ''}`.trim() || (row.author_id ? 'Name unavailable' : 'Creator not recorded'),
          department: department?.name ?? 'Company',
          createdAt: row.created_at,
          priority: ({ normal: 'Normal', important: 'High', urgent: 'High' } as const)[row.priority as 'normal' | 'important' | 'urgent'] ?? 'Normal',
          pinned: row.is_pinned,
        }
      })
    }

    const notificationError = await refreshNotifications(true)
    if (notificationError) {
      recordError('notifications', notificationError)
    }

    const { data: eventRows, error: eventError } = await supabase
      .from('events')
      .select('id,title,description,location,start_time,end_time,organizer:profiles!events_organizer_id_fkey(first_name,last_name),event_attendees(user_id,attendance_status)')
      .order('start_time')
    if (eventError) {
      recordError('events', eventError)
    } else {
      eventList.value = (eventRows ?? []).map(row => {
        const organizer = relationOne(row.organizer)
        const attendees = Array.isArray(row.event_attendees) ? row.event_attendees : []
        const ownRsvp = attendees.find((attendee: { user_id: string }) => attendee.user_id === auth.userId)
        return {
          id: row.id,
          title: row.title,
          startsAt: row.start_time,
          endsAt: row.end_time ?? null,
          location: row.location ?? '',
          description: row.description ?? '',
          organizer: `${organizer?.first_name ?? ''} ${organizer?.last_name ?? ''}`.trim() || 'Name unavailable',
          attendees: attendees.filter((attendee: { attendance_status: string }) => attendee.attendance_status === 'going').length,
          attending: ownRsvp?.attendance_status === 'going',
        }
      })
    }

    const { data: resourceRows, error: resourceError } = await supabase
      .from('resources')
      .select('id,title,description,storage_path,category,created_at,updated_at')
      .order('updated_at', { ascending: false })
    if (resourceError) {
      recordError('resources', resourceError)
    } else {
      resourceList.value = (resourceRows ?? []).map(row => ({
        id: row.id,
        title: row.title,
        category: row.category,
        description: row.description ?? '',
        format: row.storage_path?.split('.').at(-1)?.toUpperCase() ?? 'DOCUMENT',
        updatedAt: `Updated ${new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(row.updated_at ?? row.created_at))}`,
        fileUrl: row.storage_path ?? '',
      }))
    }

    const conversationRefreshError = await refreshConversations()
    if (conversationRefreshError) recordError('conversations', { message: conversationRefreshError })
    else void refreshPresence()

    if (auth.isAdmin) {
      const { data: activityRows, error: activityError } = await supabase
        .from('activity_logs')
        .select('id,action,description,created_at,profile:profiles!activity_logs_user_id_fkey(first_name,last_name)')
        .order('created_at', { ascending: false })
        .limit(10)
      if (activityError) {
        recordError('recent activity', activityError)
      } else {
        activityLogs.value = (activityRows ?? []).map(row => {
          const actor = relationOne(row.profile)
          return {
            id: row.id,
            action: row.action,
            description: row.description,
            createdAt: row.created_at,
            user: `${actor?.first_name ?? ''} ${actor?.last_name ?? ''}`.trim() || 'Northstar',
          }
        })
      }
    }

    if (errors.length > 0) {
      backendError.value = `Some Supabase data could not be loaded. ${errors.join(' · ')}`
    }
    loading.value = false
  }

  function subscribeToMessages () {
    const auth = useAuthStore()
    if (!isSupabaseConfigured || !supabase || !isUuid(auth.userId) || auth.isAdmin || !auth.canAccessEmployeeWorkspace || realtimeChannel) {
      return
    }
    startPresenceTracking()
    realtimeChannel = supabase
      .channel(`northstar-messages-${useAuthStore().userId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, payload => {
        const message = payload.new as { id: string, conversation_id: string, sender_id: string, content: string, created_at: string, edited_at?: string | null, deleted_at?: string | null, content_version?: number }
        if (!isUuid(message.id) || !isUuid(message.conversation_id) || !isUuid(message.sender_id)) return
        const conversation = conversations.value.find(item => item.id === message.conversation_id)
        if (!conversation) {
          void refreshConversations()
          return
        }
        if (conversation.messages.some(item => !item.callEvent && item.id === message.id)) {
          return
        }
        const sender = employeeList.value.find(item => item.id === message.sender_id)
        conversation.messages.push({
          id: message.id,
          author: message.sender_id === useAuthStore().userId ? 'You' : (sender ? `${sender.firstName} ${sender.lastName}` : conversation.name),
          text: message.content,
          sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(message.created_at)),
          createdAt: message.created_at,
          mine: message.sender_id === useAuthStore().userId,
          editedAt: message.edited_at ?? null,
          deletedAt: message.deleted_at ?? null,
          contentVersion: Number.isInteger(message.content_version) && (message.content_version ?? 0) > 0 ? message.content_version! : 1,
          deliveryCount: 0,
          readCount: 0,
          recipientCount: 0,
          replyTo: null,
          reactions: [],
          attachments: [],
        })
        if (message.sender_id !== useAuthStore().userId) {
          void acknowledgeMessageDelivery([{ id: message.id, version: Number.isInteger(message.content_version) && (message.content_version ?? 0) > 0 ? message.content_version! : 1 }])
        }
        conversation.messages.sort(compareChatMessages)
        if (message.sender_id !== useAuthStore().userId) {
          conversation.unread += 1
        }
        conversation.updatedAt = 'Now'
        conversations.value.sort((a, b) => compareChatMessages(b.messages.at(-1) ?? { id: '', createdAt: '' }, a.messages.at(-1) ?? { id: '', createdAt: '' }))
      })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'messages' }, () => {
        void refreshConversations()
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'northstar_call_sessions' }, () => {
        void refreshConversations()
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'message_recipient_receipts' }, () => {
        void refreshMessageReceipts()
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'message_replies' }, () => {
        void refreshMessageInteractions()
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'message_reactions' }, () => {
        void refreshMessageInteractions()
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'message_attachments' }, () => {
        void refreshMessageInteractions()
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'northstar_conversation_user_state' }, () => {
        void refreshConversations()
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'northstar_conversation_message_pins' }, () => {
        void refreshConversations()
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'northstar_conversation_typing' }, () => {
        void refreshConversationTyping()
      })
      .subscribe((status, subscriptionError) => {
        if (status === 'SUBSCRIBED') {
          messageSyncError.value = ''
          void refreshConversations()
          if (!typingRefreshTimer) typingRefreshTimer = setInterval(() => { void refreshConversationTyping() }, 4000)
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          messageSyncError.value = `Message updates are temporarily unavailable (${status}). Use Refresh messages to check for new activity.`
          backendError.value = `Supabase Realtime subscription failed: ${status}`
          logSupabaseDiagnostic('message Realtime subscription', subscriptionError ?? new Error(status))
        }
      })

    notificationChannel = supabase
      .channel(`northstar-notifications-${useAuthStore().userId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'notifications',
        filter: `user_id=eq.${useAuthStore().userId}`,
      }, payload => {
        const notification = payload.new as {
          id: string
          title: string
          message: string
          notification_type: string
          is_read: boolean
          created_at: string
          link_to?: string | null
        }
        if (!isUuid(notification.id)) return
        if (notificationList.value.some(item => item.id === notification.id)) {
          return
        }
        notificationList.value.unshift({
          id: notification.id,
          title: notification.title,
          description: notification.message,
          category: notificationCategory(notification.notification_type),
          createdAt: new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(notification.created_at)),
          unread: !notification.is_read,
          to: notificationRoute(notification.notification_type, notification.title, notification.link_to),
        })
        if (notification.notification_type === 'message') {
          void refreshConversations()
          const conversationId = notification.link_to?.match(/[?&]conversation=([0-9a-f-]+)/i)?.[1] ?? ''
          if (messageToastTimer) clearTimeout(messageToastTimer)
          messageToast.value = { title: notification.title, preview: notification.message, conversationId, notificationId: notification.id }
          messageToastTimer = setTimeout(() => { messageToast.value = null }, 7000)
        }
      })
      .subscribe((status, subscriptionError) => {
        if (status === 'SUBSCRIBED') {
          if (notificationSubscriptionInterrupted) {
            notificationSubscriptionInterrupted = false
            if (backendError.value.startsWith('Supabase notification subscription is temporarily unavailable (')) {
              backendError.value = ''
            }
            void refreshNotifications().then(error => {
              if (error) {
                backendError.value = `Could not recover missed notifications: ${error.message}`
                console.error(backendError.value, error)
              } else if (backendError.value.startsWith('Could not recover missed notifications:')) {
                backendError.value = ''
              }
            })
          }
          void refreshConversations()
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          notificationSubscriptionInterrupted = true
          backendError.value = `Supabase notification subscription is temporarily unavailable (${status}). Reconnecting automatically.`
          logSupabaseDiagnostic('notification Realtime subscription', subscriptionError ?? new Error(status))
        }
      })
  }

  function unsubscribeFromMessages () {
    stopPresenceTracking()
    notificationSubscriptionInterrupted = false
    if (typingRefreshTimer) clearInterval(typingRefreshTimer)
    typingRefreshTimer = undefined
    for (const conversationId of lastTypingSentAt.keys()) void updateConversationTyping(conversationId, false)
    lastTypingSentAt.clear()
    if (realtimeChannel && supabase) {
      void supabase.removeChannel(realtimeChannel)
    }
    if (notificationChannel && supabase) {
      void supabase.removeChannel(notificationChannel)
    }
    realtimeChannel = null
    notificationChannel = null
    if (messageToastTimer) clearTimeout(messageToastTimer)
    messageToast.value = null
  }

  function clearWorkspace () {
    unsubscribeFromMessages()
    employeeList.value = []
    announcementList.value = []
    conversations.value = []
    notificationList.value = []
    eventList.value = []
    resourceList.value = []
    departmentList.value = []
    activityLogs.value = []
    backendError.value = ''
    messageSyncError.value = ''
    receiptError.value = ''
    presenceError.value = ''
    interactionError.value = ''
    conversationStateError.value = ''
    typingError.value = ''
    loading.value = false
  }

  function refreshConversations () {
    if (conversationRefreshPromise) return conversationRefreshPromise
    conversationRefreshPromise = loadConversations().finally(() => { conversationRefreshPromise = null })
    return conversationRefreshPromise
  }

  async function loadConversations () {
    const auth = useAuthStore()
    if (!isUuid(auth.userId) || auth.isAdmin || !auth.canAccessEmployeeWorkspace || !isSupabaseConfigured || !supabase) {
      return 'Messaging requires an authenticated employee workspace and configured Supabase connection.'
    }
    const { data: memberships, error: membershipError } = await supabase
      .from('conversation_members')
      .select('conversation_id,last_read_at')
      .eq('user_id', auth.userId)
    if (membershipError) return membershipError.message
    const ids = [...new Set((memberships ?? []).map(row => row.conversation_id).filter(isUuid))]
    if (ids.length === 0) {
      conversations.value = []
      interactionError.value = ''
      conversationStateError.value = ''
      callHistoryError.value = ''
      return ''
    }
    const [stateResult, pinsResult] = await Promise.all([
      supabase.from('northstar_conversation_user_state').select('conversation_id,archived_at,unread_override').eq('user_id', auth.userId).in('conversation_id', ids),
      supabase.from('northstar_conversation_message_pins').select('conversation_id,message_id').eq('user_id', auth.userId).in('conversation_id', ids),
    ])
    conversationStateError.value = stateResult.error || pinsResult.error
      ? `Conversation archive, unread, or pin details are unavailable: ${stateResult.error?.message ?? pinsResult.error?.message}`
      : ''
    const states = new Map((stateResult.data ?? []).map(row => [row.conversation_id, row]))
    const pinsByConversation = new Map<string, string[]>()
    for (const pin of pinsResult.data ?? []) {
      const current = pinsByConversation.get(pin.conversation_id) ?? []
      current.push(pin.message_id)
      pinsByConversation.set(pin.conversation_id, current)
    }
    const [conversationResult, callHistoryResult] = await Promise.all([
      supabase
        .from('conversations')
        .select('id,updated_at,conversation_members(user_id,last_read_at,profile:profiles!conversation_members_user_id_fkey(first_name,last_name,job_title,avatar_url)),messages!messages_conversation_id_fkey(id,sender_id,content,created_at,edited_at,deleted_at,content_version)')
        .in('id', ids)
        .order('updated_at', { ascending: false }),
      supabase.from('northstar_call_sessions')
        .select('id,conversation_id,caller_id,callee_id,call_type,status,expires_at,created_at,accepted_at,ended_at')
        .in('conversation_id', ids)
        .order('created_at', { ascending: true }),
    ])
    const { data, error } = conversationResult
    callHistoryError.value = callHistoryResult.error
      ? `Call history is temporarily unavailable: ${callHistoryResult.error.message}`
      : ''
    if (callHistoryResult.error) logSupabaseDiagnostic('call history query', callHistoryResult.error)
    if (error) return error.message

    const callHistoryByConversation = new Map<string, ChatMessage[]>()
    for (const call of callHistoryResult.data ?? []) {
      if (!isUuid(call.id) || !isUuid(call.conversation_id) || !isUuid(call.caller_id) || !isUuid(call.callee_id)) continue
      if (!['audio', 'video'].includes(call.call_type) || typeof call.status !== 'string' || !call.created_at) continue
      const outgoing = call.caller_id === auth.userId
      const status = String(call.status)
      const statusLabel = status === 'ringing' && Date.parse(call.expires_at) <= Date.now() ? 'Invitation expired' : ({
        ringing: 'No answer yet', accepted: 'In progress', declined: 'Declined', cancelled: 'Cancelled',
        missed: 'Missed', ended: 'Completed', failed: 'Failed',
      } as Record<string, string>)[status] ?? 'Call update'
      const callType = call.call_type as 'audio' | 'video'
      const acceptedAt = typeof call.accepted_at === 'string' ? Date.parse(call.accepted_at) : Number.NaN
      const endedAt = typeof call.ended_at === 'string' ? Date.parse(call.ended_at) : Number.NaN
      const durationSeconds = status === 'ended'
        && Number.isFinite(acceptedAt)
        && Number.isFinite(endedAt)
        && endedAt >= acceptedAt
        ? Math.floor((endedAt - acceptedAt) / 1000)
        : null
      const entry: ChatMessage = {
        id: `call:${call.id}`,
        author: outgoing ? 'You' : 'Colleague',
        text: `${outgoing ? 'Outgoing' : 'Incoming'} ${callType} call · ${statusLabel}`,
        sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(call.created_at)),
        createdAt: call.created_at,
        mine: outgoing,
        editedAt: null,
        deletedAt: null,
        contentVersion: 1,
        deliveryCount: 0,
        readCount: 0,
        recipientCount: 0,
        replyTo: null,
        reactions: [],
        attachments: [],
        callEvent: { callType, status, expiresAt: call.expires_at, durationSeconds },
      }
      const entries = callHistoryByConversation.get(call.conversation_id) ?? []
      entries.push(entry)
      callHistoryByConversation.set(call.conversation_id, entries)
    }

    conversations.value = (data ?? []).map(row => {
      const members = Array.isArray(row.conversation_members) ? row.conversation_members : []
      const peer = members.find((member: { user_id: string }) => member.user_id !== auth.userId)
      const ownMembership = members.find((member: { user_id: string }) => member.user_id === auth.userId)
      const profile = relationOne(peer?.profile)
      const firstName = profile?.first_name ?? 'Colleague'
      const lastName = profile?.last_name ?? ''
      const messages = sortByCreatedAt(Array.isArray(row.messages) ? row.messages : [])
      const state = states.get(row.id)
      const unreadCount = messages.filter((message: { sender_id: string, created_at: string }) => message.sender_id !== auth.userId && (!ownMembership?.last_read_at || message.created_at > ownMembership.last_read_at)).length
      return {
        id: row.id,
        employeeId: peer?.user_id ?? '',
        name: `${firstName} ${lastName}`.trim(),
        title: profile?.job_title ?? '',
        initials: `${firstName[0] ?? ''}${lastName[0] ?? ''}`.toUpperCase(),
        color: '#dce8ba',
        online: null,
        lastSeenAt: null,
        unread: state?.unread_override ? Math.max(1, unreadCount) : unreadCount,
        archived: Boolean(state?.archived_at),
        markedUnread: Boolean(state?.unread_override),
        pinnedMessageIds: pinsByConversation.get(row.id) ?? [],
        typingUserIds: [],
        updatedAt: row.updated_at ? new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(row.updated_at)) : '',
        messages: [
          ...messages.map((message: { id: string, sender_id: string, content: string, created_at: string, edited_at?: string | null, deleted_at?: string | null, content_version?: number }) => ({
          id: message.id,
          author: message.sender_id === auth.userId ? 'You' : `${firstName} ${lastName}`.trim(),
          text: message.deleted_at ? 'This message was deleted' : message.content,
          sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(message.created_at)),
          createdAt: message.created_at,
          mine: message.sender_id === auth.userId,
          editedAt: message.edited_at ?? null,
          deletedAt: message.deleted_at ?? null,
          contentVersion: Number.isInteger(message.content_version) && (message.content_version ?? 0) > 0 ? message.content_version! : 1,
          deliveryCount: 0,
          readCount: 0,
          recipientCount: 0,
          replyTo: null,
          reactions: [],
          attachments: [],
          })),
          ...(callHistoryByConversation.get(row.id) ?? []),
        ].sort(compareChatMessages),
      }
    }).filter(item => item.messages.length > 0)
    conversations.value.sort((a, b) => compareChatMessages(b.messages.at(-1) ?? { id: '', createdAt: '' }, a.messages.at(-1) ?? { id: '', createdAt: '' }))
    applyConversationPresence()
    const incomingMessages = conversations.value.flatMap(conversation => conversation.messages.filter(message => !message.callEvent && !message.mine && !message.deletedAt))
    if (incomingMessages.length > 0) void acknowledgeMessageDelivery(incomingMessages.map(message => ({ id: message.id, version: message.contentVersion })))
    void refreshMessageReceipts()
    void refreshMessageInteractions()
    void refreshConversationTyping()
    return ''
  }

  function applyConversationPresence () {
    for (const conversation of conversations.value) {
      const conversationEmployeeId = normalizeUuid(conversation.employeeId)
      const peer = conversationEmployeeId
        ? employeeList.value.find(employee => normalizeUuid(employee.id) === conversationEmployeeId)
        : undefined
      conversation.online = peer?.online ?? null
      conversation.lastSeenAt = peer?.lastSeenAt ?? null
    }
  }

  async function refreshPresence () {
    if (!supabase || !isSupabaseConfigured) {
      return false
    }
    // Restrict the request to the approved, active employee directory already
    // loaded for this workspace. The RPC must still enforce access server-side;
    // client-side scoping is only data minimization.
    const ids = [...new Set(employeeList.value.map(employee => employee.id).filter(isUuid))]
    const requestGeneration = ++presenceRequestGeneration
    if (ids.length === 0) {
      for (const employee of employeeList.value) {
        employee.online = null
        employee.lastSeenAt = null
      }
      presenceError.value = ''
      return true
    }
    let data: unknown
    let error: unknown
    try {
      const result = await supabase.rpc('northstar_list_employee_presence', { p_user_ids: ids })
      data = result.data
      error = result.error
    } catch (reason) {
      error = reason
    }
    if (error) {
      const message = error instanceof Error ? error.message : (error as { message?: string }).message ?? 'The request failed.'
      logSupabaseDiagnostic('employee presence query', error)
      if (import.meta.env.DEV) {
        const failedRows: unknown[] = Array.isArray(data) ? data : data && typeof data === 'object' ? [data] : []
        const requestedUserIds = ids.map(normalizeUuid).filter((id): id is string => id !== null)
        const failedReturnedUserIds = failedRows.map(row => row && typeof row === 'object'
          ? normalizeUuid((row as { user_id?: unknown }).user_id)
          : null).filter((id): id is string => id !== null)
        console.info('[NorthStar presence RPC diagnostic]', {
          success: false,
          responseType: Array.isArray(data) ? 'array' : data === null ? 'null' : typeof data,
          responseKeys: data && typeof data === 'object' && !Array.isArray(data) ? Object.keys(data) : [],
          rowKeys: [...new Set(failedRows.flatMap(row => row && typeof row === 'object' ? Object.keys(row) : []))],
          requestedUserIdCount: ids.length,
          requestedUserIds,
          returnedUserIds: failedReturnedUserIds,
          parsedPresenceRecordCount: 0,
          matchedEmployeeCount: 0,
          matchedConversationParticipantCount: 0,
          employeeMappings: employeeList.value.map(employee => ({
            userId: normalizeUuid(employee.id) ?? '[invalid UUID]',
            wasRequested: Boolean(normalizeUuid(employee.id) && requestedUserIds.includes(normalizeUuid(employee.id)!)),
            returnedMatchingId: Boolean(normalizeUuid(employee.id) && failedReturnedUserIds.includes(normalizeUuid(employee.id)!)),
            parsed: false,
            status: 'unknown',
            reason: 'presence-list RPC returned an error',
          })),
          conversationMappings: conversations.value.map(conversation => {
            const conversationUserId = normalizeUuid(conversation.employeeId)
            const directoryMatch = Boolean(conversationUserId && employeeList.value.some(employee => normalizeUuid(employee.id) === conversationUserId))
            return {
              conversationUserId: conversationUserId ?? '[invalid UUID]',
              directoryMatch,
              presenceMatch: false,
              normalizedIdsMatch: directoryMatch,
              status: 'unknown',
              reason: 'presence-list RPC returned an error',
            }
          }),
          adejareEmployeeIds: {
            directory: employeeList.value.filter(employee => employee.firstName.trim().toLocaleLowerCase() === 'adejare'
              && employee.lastName.trim().toLocaleLowerCase() === 'ade').map(employee => normalizeUuid(employee.id)).filter(Boolean),
            conversation: conversations.value.filter(conversation => conversation.name.trim().toLocaleLowerCase() === 'adejare ade')
              .map(conversation => normalizeUuid(conversation.employeeId)).filter(Boolean),
          },
          errorCode: error && typeof error === 'object' ? (error as { code?: unknown }).code ?? null : null,
          staleResponse: requestGeneration !== presenceRequestGeneration,
        })
      }
      if (requestGeneration !== presenceRequestGeneration) return false
      for (const employee of employeeList.value) {
        employee.online = null
        employee.lastSeenAt = null
      }
      applyConversationPresence()
      presenceError.value = `Could not refresh employee presence: ${message}`
      return false
    }
    const rows: unknown[] = Array.isArray(data)
      ? data
      : data && typeof data === 'object'
        ? [data]
        : []
    const requestedIds = new Set(ids.map(normalizeUuid).filter((id): id is string => id !== null))
    const returnedUserIds = rows.map(row => row && typeof row === 'object'
      ? normalizeUuid((row as { user_id?: unknown }).user_id)
      : null).filter((id): id is string => id !== null)
    const presenceByUser = new Map<string, { last_seen_at: string | null, is_online: boolean }>()
    for (const row of rows) {
      if (!row || typeof row !== 'object') continue
      const presence = row as { user_id?: unknown, last_seen_at?: unknown, is_online?: unknown }
      const userId = normalizeUuid(presence.user_id)
      if (!userId || !requestedIds.has(userId) || typeof presence.is_online !== 'boolean') continue
      const lastSeenAt = typeof presence.last_seen_at === 'string' && Number.isFinite(Date.parse(presence.last_seen_at))
        ? presence.last_seen_at
        : null
      const previous = presenceByUser.get(userId)
      const previousTimestamp = previous?.last_seen_at ? Date.parse(previous.last_seen_at) : Number.NEGATIVE_INFINITY
      const currentTimestamp = lastSeenAt ? Date.parse(lastSeenAt) : Number.NEGATIVE_INFINITY
      presenceByUser.set(userId, {
        is_online: presence.is_online || previous?.is_online === true,
        last_seen_at: currentTimestamp >= previousTimestamp ? lastSeenAt : previous?.last_seen_at ?? null,
      })
    }
    if (import.meta.env.DEV) {
      const employeeMappings = employeeList.value.map(employee => {
        const employeeId = normalizeUuid(employee.id)
        const returnedRows = employeeId ? rows.filter(row => row && typeof row === 'object'
          && normalizeUuid((row as { user_id?: unknown }).user_id) === employeeId) : []
        const parsedPresence = employeeId ? presenceByUser.get(employeeId) : undefined
        let reason: string | null = null
        if (!employeeId) reason = 'employee directory ID is not a valid UUID'
        else if (!requestedIds.has(employeeId)) reason = 'employee directory ID was not included in p_user_ids'
        else if (!returnedRows.length) reason = 'RPC returned no record for this requested ID'
        else if (!parsedPresence) reason = 'matching RPC record was rejected because is_online was not a boolean'
        return {
          userId: employeeId ?? '[invalid UUID]',
          wasRequested: Boolean(employeeId && requestedIds.has(employeeId)),
          returnedMatchingId: Boolean(employeeId && returnedUserIds.includes(employeeId)),
          parsed: Boolean(parsedPresence),
          status: parsedPresence ? (parsedPresence.is_online ? 'online' : 'offline') : 'unknown',
          reason,
        }
      })
      const conversationMappings = conversations.value.map(conversation => {
        const conversationUserId = normalizeUuid(conversation.employeeId)
        const directoryEmployee = conversationUserId
          ? employeeList.value.find(employee => normalizeUuid(employee.id) === conversationUserId)
          : undefined
        const directoryUserId = normalizeUuid(directoryEmployee?.id)
        const parsedPresence = directoryUserId ? presenceByUser.get(directoryUserId) : undefined
        let reason: string | null = null
        if (!conversationUserId) reason = 'conversation participant ID is not a valid UUID'
        else if (!directoryEmployee) reason = 'conversation participant has no matching employee-directory profile'
        else if (!directoryUserId || !requestedIds.has(directoryUserId)) reason = 'directory profile ID was not included in p_user_ids'
        else if (!parsedPresence) reason = 'RPC returned no usable presence record for the directory ID'
        return {
          conversationUserId: conversationUserId ?? '[invalid UUID]',
          directoryUserId,
          directoryMatch: Boolean(directoryEmployee),
          presenceMatch: Boolean(parsedPresence),
          normalizedIdsMatch: Boolean(conversationUserId && directoryUserId && conversationUserId === directoryUserId),
          wasRequested: Boolean(directoryUserId && requestedIds.has(directoryUserId)),
          returnedMatchingId: Boolean(directoryUserId && returnedUserIds.includes(directoryUserId)),
          status: parsedPresence ? (parsedPresence.is_online ? 'online' : 'offline') : 'unknown',
          reason,
        }
      })
      const adejareDirectoryIds = employeeList.value
        .filter(employee => employee.firstName.trim().toLocaleLowerCase() === 'adejare'
          && employee.lastName.trim().toLocaleLowerCase() === 'ade')
        .map(employee => normalizeUuid(employee.id))
        .filter((id): id is string => id !== null)
      const adejareConversationIds = conversations.value
        .filter(conversation => conversation.name.trim().toLocaleLowerCase() === 'adejare ade')
        .map(conversation => normalizeUuid(conversation.employeeId))
        .filter((id): id is string => id !== null)
      console.info('[NorthStar presence RPC diagnostic]', {
        success: true,
        responseType: Array.isArray(data) ? 'array' : data && typeof data === 'object' ? 'object' : typeof data,
        responseKeys: data && typeof data === 'object' && !Array.isArray(data) ? Object.keys(data) : [],
        rowKeys: [...new Set(rows.flatMap(row => row && typeof row === 'object' ? Object.keys(row) : []))],
        requestedUserIdCount: ids.length,
        requestedUserIds: [...requestedIds],
        returnedUserIds,
        parsedPresenceRecordCount: presenceByUser.size,
        matchedEmployeeCount: employeeMappings.filter(employee => employee.parsed).length,
        matchedConversationParticipantCount: conversationMappings.filter(participant => participant.directoryMatch && participant.presenceMatch).length,
        employeeMappings,
        conversationMappings,
        adejareEmployeeIds: {
          directory: [...new Set(adejareDirectoryIds)],
          conversation: [...new Set(adejareConversationIds)],
        },
        staleResponse: requestGeneration !== presenceRequestGeneration,
      })
    }
    if (requestGeneration !== presenceRequestGeneration) return false
    for (const employee of employeeList.value) {
      const employeeId = normalizeUuid(employee.id)
      const presence = employeeId ? presenceByUser.get(employeeId) : undefined
      employee.online = typeof presence?.is_online === 'boolean' ? presence.is_online : null
      employee.lastSeenAt = typeof presence?.last_seen_at === 'string' && Number.isFinite(Date.parse(presence.last_seen_at))
        ? presence.last_seen_at
        : null
    }
    applyConversationPresence()
    presenceError.value = ''
    return true
  }

  async function sendPresenceHeartbeat () {
    if (!supabase || !isSupabaseConfigured || document.visibilityState !== 'visible' || presenceHeartbeatInFlight) {
      return
    }
    presenceHeartbeatInFlight = true
    try {
      let error: unknown
      try {
        const result = await supabase.rpc('northstar_presence_heartbeat')
        error = result.error
      } catch (reason) {
        error = reason
      }
      if (error) logSupabaseDiagnostic('presence heartbeat', error)
      const refreshed = await refreshPresence()
      if (error) {
        const refreshFailure = refreshed ? '' : ` ${presenceError.value}`
        const message = error instanceof Error ? error.message : (error as { message?: string }).message ?? 'The request failed.'
        presenceError.value = `Presence heartbeat failed: ${message}.${refreshFailure}`
      }
    } finally {
      presenceHeartbeatInFlight = false
    }
  }

  function startPresenceTracking () {
    stopPresenceTracking()
    if (typeof document === 'undefined') return
    presenceVisibilityHandler = () => {
      if (document.visibilityState === 'visible') void sendPresenceHeartbeat()
    }
    document.addEventListener('visibilitychange', presenceVisibilityHandler)
    void sendPresenceHeartbeat()
    presenceHeartbeatTimer = setInterval(() => { void sendPresenceHeartbeat() }, 30_000)
  }

  function stopPresenceTracking () {
    if (presenceHeartbeatTimer) clearInterval(presenceHeartbeatTimer)
    presenceHeartbeatTimer = undefined
    if (presenceVisibilityHandler && typeof document !== 'undefined') {
      document.removeEventListener('visibilitychange', presenceVisibilityHandler)
    }
    presenceVisibilityHandler = undefined
  }

  async function startConversation (employeeId: string) {
    const auth = useAuthStore()
    if (!isUuid(employeeId) || !isUuid(auth.userId) || employeeId === auth.userId || auth.isAdmin || !auth.canAccessEmployeeWorkspace) {
      backendError.value = 'Choose a valid employee before starting a conversation.'
      return ''
    }
    const existing = conversations.value.find(item => item.employeeId === employeeId)
    if (existing || !isSupabaseConfigured || !supabase) {
      return existing?.id ?? ''
    }
    backendError.value = ''
    const { data, error } = await supabase.rpc('create_conversation', { p_member_ids: [employeeId] })
    if (error) {
      backendError.value = `Could not start conversation: ${error.message}`
      console.error(backendError.value, error)
      return ''
    }
    if (typeof data !== 'string') {
      backendError.value = 'Could not start conversation: Supabase returned an unexpected conversation ID.'
      return ''
    }
    return data
  }

  async function sendFirstMessage (employeeId: string, text: string) {
    const trimmed = text.trim()
    if (!trimmed) return false
    const id = await startConversation(employeeId)
    if (!id || !isSupabaseConfigured || !supabase) return false
    if (!await persistMessage(id, trimmed)) {
      return false
    }
    const refreshError = await refreshConversations()
    if (refreshError) backendError.value = `Message sent, but the conversation could not be refreshed: ${refreshError}`
    else backendError.value = ''
    return true
  }

  async function sendMessage (conversationId: string, text: string, replyToMessageId?: string) {
    if (!isUuid(conversationId) || !isUuid(useAuthStore().userId)) return false
    const conversation = conversations.value.find(item => item.id === conversationId)
    const trimmed = text.trim()
    if (!conversation || !trimmed) {
      return false
    }

    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Sending messages requires a configured Northstar Supabase connection.'
      return false
    }

    return persistMessage(conversationId, trimmed, replyToMessageId)
  }

  async function persistMessage (conversationId: string, trimmed: string, replyToMessageId?: string) {
    const conversation = conversations.value.find(item => item.id === conversationId)
    if (!isSupabaseConfigured || !supabase) return false
    if (replyToMessageId && (!isUuid(replyToMessageId) || !conversation?.messages.some(message => message.id === replyToMessageId))) {
      backendError.value = 'The message you are replying to is unavailable.'
      return false
    }
    const requestKey = await messageRequestKey(useAuthStore().userId, conversationId, trimmed, replyToMessageId)
    let requestId = pendingMessageRequests.get(requestKey)
    if (!requestId && requestKey.startsWith('northstar.pending:')) {
      try {
        requestId = sessionStorage.getItem(requestKey) ?? undefined
      } catch {
        // Keep retries idempotent for the current runtime if browser storage is unavailable.
      }
    }
    if (!requestId) {
      requestId = crypto.randomUUID()
      pendingMessageRequests.set(requestKey, requestId)
      if (requestKey.startsWith('northstar.pending:')) {
        try {
          sessionStorage.setItem(requestKey, requestId)
        } catch {
          // The in-memory request ID still protects retries until this page is closed.
        }
      }
    }
    const { data, error } = replyToMessageId
      ? await supabase.rpc('northstar_send_message_reply', {
        p_conversation_id: conversationId,
        p_content: trimmed,
        p_client_request_id: requestId,
        p_reply_to_message_id: replyToMessageId,
      })
      : await supabase.rpc('northstar_send_message', {
        p_conversation_id: conversationId,
        p_content: trimmed,
        p_client_request_id: requestId,
      })
    if (error) {
      backendError.value = `Could not send message. Retry to safely check this same send request: ${error.message}`
      console.error(backendError.value, error)
      return false
    }
    const row = Array.isArray(data) ? data[0] : data
    if (!row || typeof row.id !== 'string' || typeof row.created_at !== 'string') {
      backendError.value = 'The message was accepted, but the server returned an unexpected response. Refresh the inbox before retrying.'
      return false
    }
    pendingMessageRequests.delete(requestKey)
    if (requestKey.startsWith('northstar.pending:')) {
      try {
        sessionStorage.removeItem(requestKey)
      } catch {
        // The send is already confirmed; storage cleanup is best-effort.
      }
    }
    if (conversation && !conversation.messages.some(item => item.id === row.id)) {
      conversation.messages.push({
        id: row.id,
        author: 'You',
        text: row.deleted_at ? 'This message was deleted' : row.content,
        sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(row.created_at)),
        createdAt: row.created_at,
        mine: true,
        editedAt: row.edited_at ?? null,
        deletedAt: row.deleted_at ?? null,
        contentVersion: Number.isInteger(row.content_version) && row.content_version > 0 ? row.content_version : 1,
        deliveryCount: 0,
        readCount: 0,
        recipientCount: 0,
        replyTo: null,
        reactions: [],
        attachments: [],
      })
    }
    if (conversation) {
      conversation.updatedAt = 'Now'
      conversations.value.sort((a, b) => compareChatMessages(b.messages.at(-1) ?? { id: '', createdAt: '' }, a.messages.at(-1) ?? { id: '', createdAt: '' }))
    } else {
      await refreshConversations()
    }
    if (replyToMessageId) await refreshMessageInteractions()
    backendError.value = ''
    void refreshMessageReceipts()
    return true
  }

  async function acknowledgeMessageDelivery (messages: { id: string, version: number }[]) {
    if (!supabase || !isSupabaseConfigured || !isUuid(useAuthStore().userId)) return false
    const receipts = [...new Map(messages.filter(message => isUuid(message.id) && Number.isInteger(message.version) && message.version > 0).map(message => [message.id, message.version])).entries()].map(([message_id, message_version]) => ({ message_id, message_version }))
    if (receipts.length === 0) return false
    const { error } = await supabase.rpc('northstar_acknowledge_message_delivery', { p_message_versions: receipts })
    if (error) {
      console.warn('Message delivery acknowledgement could not be recorded.', error.message)
      messageSyncError.value = `A message delivery receipt could not be recorded: ${error.message}`
      return false
    }
    messageSyncError.value = ''
    return true
  }

  async function acknowledgeMessageVisible (messageId: string, messageVersion: number) {
    if (!isUuid(messageId) || !Number.isInteger(messageVersion) || messageVersion < 1 || !supabase || !isSupabaseConfigured || !isUuid(useAuthStore().userId)) return false
    const { error } = await supabase.rpc('northstar_acknowledge_message_visible', { p_message_id: messageId, p_message_version: messageVersion })
    if (error) {
      console.warn('Visible message acknowledgement could not be recorded.', error.message)
      messageSyncError.value = `A message read receipt could not be recorded: ${error.message}`
      return false
    }
    messageSyncError.value = ''
    await refreshMessageReceipts()
    return true
  }

  async function refreshMessageReceipts () {
    if (!supabase || !isSupabaseConfigured || !isUuid(useAuthStore().userId)) {
      return
    }
    const ownMessageIds = conversations.value.flatMap(conversation => conversation.messages.filter(message => !message.callEvent && message.mine && !message.deletedAt).map(message => message.id))
    if (ownMessageIds.length === 0) {
      for (const conversation of conversations.value) {
        for (const message of conversation.messages) {
          if (!message.mine) {
            continue
          }
          message.recipientCount = 0
          message.deliveryCount = 0
          message.readCount = 0
        }
      }
      receiptError.value = ''
      return
    }
    const { data, error } = await supabase.rpc('northstar_list_message_receipts', { p_message_ids: ownMessageIds })
    if (error) {
      console.warn('Message receipt details are temporarily unavailable.', error.message)
      receiptError.value = `Could not refresh delivery and read receipts: ${error.message}`
      return
    }
    receiptError.value = ''
    const receipts = (Array.isArray(data) ? data : []) as { message_id: string, recipient_id: string, delivered_at: string | null, read_at: string | null }[]
    for (const conversation of conversations.value) {
      for (const message of conversation.messages) {
        if (!message.mine) continue
        const messageReceipts = receipts.filter(receipt => receipt.message_id === message.id)
        message.recipientCount = messageReceipts.length
        message.deliveryCount = messageReceipts.filter(receipt => receipt.delivered_at).length
        message.readCount = messageReceipts.filter(receipt => receipt.read_at).length
      }
    }
  }

  async function refreshMessageInteractions () {
    if (!supabase || !isSupabaseConfigured) return
    const messages = conversations.value.flatMap(conversation => conversation.messages.filter(message => !message.callEvent))
    const ids = messages.map(message => message.id).filter(isUuid)
    if (!ids.length) {
      interactionError.value = ''
      return
    }
    const [replyResult, reactionResult, attachmentResult] = await Promise.all([
      supabase.from('message_replies').select('message_id,reply_to_message_id').in('message_id', ids),
      supabase.from('message_reactions').select('message_id,user_id,emoji').in('message_id', ids),
      supabase.from('message_attachments').select('id,message_id,storage_path,file_name,mime_type,size_bytes,duration_seconds').in('message_id', ids),
    ])
    if (replyResult.error || reactionResult.error || attachmentResult.error) {
      interactionError.value = `Could not refresh message details: ${replyResult.error?.message ?? reactionResult.error?.message ?? attachmentResult.error?.message}`
      return
    }
    interactionError.value = ''
    const byId = new Map(messages.map(message => [message.id, message]))
    const userId = useAuthStore().userId
    for (const message of messages) {
      const relation = (replyResult.data ?? []).find(row => row.message_id === message.id)
      const target = relation ? byId.get(relation.reply_to_message_id) : undefined
      message.replyTo = relation ? {
        id: relation.reply_to_message_id,
        author: target?.author ?? 'Colleague',
        text: target?.deletedAt ? 'This message was deleted' : target?.text ?? 'Message unavailable',
      } : null
      const grouped = new Map<string, { emoji: string, count: number, reactedByMe: boolean }>()
      for (const row of (reactionResult.data ?? []).filter(item => item.message_id === message.id)) {
        const item = grouped.get(row.emoji) ?? { emoji: row.emoji, count: 0, reactedByMe: false }
        item.count += 1
        item.reactedByMe ||= row.user_id === userId
        grouped.set(row.emoji, item)
      }
      message.reactions = [...grouped.values()]
      message.attachments = (attachmentResult.data ?? []).filter(row => row.message_id === message.id).map(row => ({
        id: row.id,
        storagePath: row.storage_path,
        fileName: row.file_name,
        mimeType: row.mime_type,
        sizeBytes: row.size_bytes,
        durationSeconds: row.duration_seconds,
      }))
    }
  }

  async function toggleMessageReaction (messageId: string, emoji: string) {
    const message = findMessage(messageId)
    const userId = useAuthStore().userId
    const allowedEmoji = ['👍', '❤️', '😂', '😮', '😢', '🙏']
    if (!message || message.deletedAt || !allowedEmoji.includes(emoji) || !isUuid(userId) || !supabase || !isSupabaseConfigured) return false
    const selected = message.reactions.find(reaction => reaction.emoji === emoji)?.reactedByMe
    const result = selected
      ? await supabase.from('message_reactions').delete().eq('message_id', messageId).eq('user_id', userId).eq('emoji', emoji)
      : await supabase.from('message_reactions').insert({ message_id: messageId, user_id: userId, emoji })
    if (result.error) {
      backendError.value = `Could not update reaction: ${result.error.message}`
      await refreshMessageInteractions()
      return false
    }
    backendError.value = ''
    await refreshMessageInteractions()
    return true
  }

  async function sendMessageAttachment (
    conversationId: string,
    file: File,
    caption: string,
    durationSeconds: number | null,
    onProgress: (percent: number) => void,
    signal: AbortSignal,
  ) {
    const auth = useAuthStore()
    const mimeType = file.type.split(';')[0]?.trim().toLowerCase() ?? ''
    const audioTypes = ['audio/webm', 'audio/ogg', 'audio/mp4', 'audio/mpeg', 'audio/wav']
    const allowedTypes = [
      'image/jpeg', 'image/png', 'image/gif', 'image/webp',
      'video/mp4', 'video/webm',
      'application/pdf', 'text/plain', 'text/csv',
      'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      ...audioTypes,
    ]
    const isAudio = audioTypes.includes(mimeType)
    const maxBytes = isAudio ? 10 * 1024 * 1024 : 25 * 1024 * 1024
    if (!supabase || !isSupabaseConfigured || !isUuid(conversationId) || !isUuid(auth.userId) || auth.isAdmin || !auth.canAccessEmployeeWorkspace) {
      backendError.value = 'Sign in with an employee account and open an authorized conversation before uploading.'
      return false
    }
    if (!allowedTypes.includes(mimeType) || file.size < 1 || file.size > maxBytes) {
      backendError.value = isAudio
        ? 'Voice recordings must use a supported audio format and be no larger than 10 MB.'
        : 'Choose a supported image, video or document file no larger than 25 MB.'
      return false
    }
    if (isAudio && (!Number.isFinite(durationSeconds) || !durationSeconds || durationSeconds > 300)) {
      backendError.value = 'Voice recordings must be between 1 second and 5 minutes.'
      return false
    }
    if (signal.aborted) return false

    const extensionByType: Record<string, string> = {
      'image/jpeg': 'jpg', 'image/png': 'png', 'image/gif': 'gif', 'image/webp': 'webp',
      'video/mp4': 'mp4', 'video/webm': 'webm',
      'application/pdf': 'pdf', 'text/plain': 'txt', 'text/csv': 'csv',
      'application/msword': 'doc', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
      'application/vnd.ms-excel': 'xls', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
      'application/vnd.ms-powerpoint': 'ppt', 'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
      'audio/webm': 'webm', 'audio/ogg': 'ogg', 'audio/mp4': 'm4a', 'audio/mpeg': 'mp3', 'audio/wav': 'wav',
    }
    let requestKey: string
    try {
      requestKey = await attachmentRequestKey(auth.userId, conversationId, file, caption, durationSeconds)
    } catch (error) {
      backendError.value = error instanceof Error ? error.message : 'Could not prepare a safe attachment retry key.'
      return false
    }
    let request = pendingAttachmentRequests.get(requestKey)
    if (!request) {
      try {
        const saved = sessionStorage.getItem(requestKey)
        request = saved ? JSON.parse(saved) as { requestId: string, path: string } : undefined
      } catch {
        request = undefined
      }
    }
    if (!request) {
      const requestId = crypto.randomUUID()
      request = {
        requestId,
        path: `${conversationId}/${auth.userId}/${requestId}.${extensionByType[mimeType]}`,
      }
      pendingAttachmentRequests.set(requestKey, request)
      try { sessionStorage.setItem(requestKey, JSON.stringify(request)) } catch { /* In-memory retry remains available. */ }
    }
    if (!isUuid(request.requestId) || request.path !== `${conversationId}/${auth.userId}/${request.requestId}.${extensionByType[mimeType]}`) {
      pendingAttachmentRequests.delete(requestKey)
      const requestId = crypto.randomUUID()
      request = {
        requestId,
        path: `${conversationId}/${auth.userId}/${requestId}.${extensionByType[mimeType]}`,
      }
      pendingAttachmentRequests.set(requestKey, request)
      try { sessionStorage.setItem(requestKey, JSON.stringify(request)) } catch { /* In-memory retry remains available. */ }
    }

    backendError.value = ''
    try {
      const uploadFile = file.type === mimeType ? file : new File([file], file.name, { type: mimeType, lastModified: file.lastModified })
      await uploadPrivateMessageObject(request.path, uploadFile, onProgress, signal)
    } catch (error) {
      backendError.value = error instanceof Error ? error.message : 'The attachment upload failed.'
      return false
    }

    const { data, error } = await supabase.rpc('northstar_send_message_attachment', {
      p_conversation_id: conversationId,
      p_storage_path: request.path,
      p_file_name: file.name.slice(0, 180),
      p_mime_type: mimeType,
      p_size_bytes: file.size,
      p_caption: caption.trim(),
      p_client_request_id: request.requestId,
      p_duration_seconds: durationSeconds,
    })
    if (error) {
      backendError.value = `The file uploaded, but its message could not be saved: ${error.message}. Retry with the same file to safely finish or check the conversation first.`
      return false
    }
    const row = Array.isArray(data) ? data[0] : data
    if (!row || typeof row.id !== 'string') {
      backendError.value = 'The attachment message returned an unexpected response. Refresh the conversation before retrying.'
      return false
    }
    pendingAttachmentRequests.delete(requestKey)
    try { sessionStorage.removeItem(requestKey) } catch { /* Successful upload already has a server record. */ }
    backendError.value = ''
    const refreshError = await refreshConversations()
    if (refreshError) backendError.value = `Attachment sent, but the conversation could not be refreshed: ${refreshError}`
    return true
  }

  async function getMessageAttachmentUrl (storagePath: string) {
    if (!supabase || !isSupabaseConfigured || !storagePath) return ''
    const { data, error } = await supabase.storage.from('northstar-message-attachments').createSignedUrl(storagePath, 300)
    if (error) {
      backendError.value = `Could not open this private attachment: ${error.message}`
      return ''
    }
    return data.signedUrl
  }

  async function editMessage (messageId: string, content: string) {
    const message = findMessage(messageId)
    const trimmed = content.trim()
    if (!message || !message.mine || message.deletedAt || !trimmed || !supabase || !isSupabaseConfigured) return false
    const { error } = await supabase.rpc('northstar_edit_message', { p_message_id: messageId, p_content: trimmed })
    if (error) {
      backendError.value = `Could not edit message: ${error.message}`
      return false
    }
    backendError.value = ''
    await refreshConversations()
    return true
  }

  async function deleteMessageForEveryone (messageId: string) {
    const message = findMessage(messageId)
    if (!message || !message.mine || message.deletedAt || !supabase || !isSupabaseConfigured) return false
    const { error } = await supabase.rpc('northstar_delete_message_for_everyone', { p_message_id: messageId })
    if (error) {
      backendError.value = `Could not delete message: ${error.message}`
      return false
    }
    backendError.value = ''
    await refreshConversations()
    return true
  }

  async function hideMessageForMe (messageId: string) {
    const message = findMessage(messageId)
    if (!message || !supabase || !isSupabaseConfigured) return false
    const { error } = await supabase.rpc('northstar_hide_message_for_me', { p_message_id: messageId })
    if (error) {
      backendError.value = `Could not hide message: ${error.message}`
      return false
    }
    for (const conversation of conversations.value) conversation.messages = conversation.messages.filter(item => item.id !== messageId)
    backendError.value = ''
    await refreshConversations()
    return true
  }

  function findMessage (messageId: string) {
    for (const conversation of conversations.value) {
      const message = conversation.messages.find(item => item.id === messageId)
      if (message) return message
    }
    return undefined
  }

  async function markConversationRead (conversationId: string) {
    if (!isUuid(conversationId) || !isUuid(useAuthStore().userId)) return
    const conversation = conversations.value.find(item => item.id === conversationId)
    if (!conversation) {
      return
    }
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Marking messages as read requires a configured Northstar Supabase connection.'
      return
    }
    const { error } = await supabase.rpc('northstar_update_conversation_user_state', {
      p_conversation_id: conversationId,
      p_action: 'mark_read',
    })
    if (error) {
      backendError.value = `Could not mark messages as read: ${error.message}`
      console.error(backendError.value, error)
      return
    }
    conversation.unread = 0
    conversation.markedUnread = false
  }

  async function setConversationState (conversationId: string, action: 'archive' | 'restore' | 'mark_unread') {
    const conversation = conversations.value.find(item => item.id === conversationId)
    if (!conversation || !supabase || !isSupabaseConfigured) return false
    const { error } = await supabase.rpc('northstar_update_conversation_user_state', {
      p_conversation_id: conversationId,
      p_action: action,
    })
    if (error) {
      backendError.value = `Could not ${action.replace('_', ' ')} conversation: ${error.message}`
      return false
    }
    if (action === 'archive') conversation.archived = true
    if (action === 'restore') conversation.archived = false
    if (action === 'mark_unread') {
      conversation.markedUnread = true
      conversation.unread = Math.max(1, conversation.unread)
    }
    backendError.value = ''
    return true
  }

  async function setMessagePinned (conversationId: string, messageId: string, pinned: boolean) {
    const conversation = conversations.value.find(item => item.id === conversationId)
    if (!conversation || !conversation.messages.some(message => message.id === messageId) || !supabase || !isSupabaseConfigured) return false
    const { error } = await supabase.rpc('northstar_set_conversation_message_pin', {
      p_conversation_id: conversationId,
      p_message_id: messageId,
      p_is_pinned: pinned,
    })
    if (error) {
      backendError.value = `Could not ${pinned ? 'pin' : 'unpin'} message: ${error.message}`
      return false
    }
    conversation.pinnedMessageIds = pinned
      ? [...new Set([...conversation.pinnedMessageIds, messageId])]
      : conversation.pinnedMessageIds.filter(id => id !== messageId)
    backendError.value = ''
    return true
  }

  async function updateConversationTyping (conversationId: string, isTyping: boolean) {
    const auth = useAuthStore()
    if (!supabase || !isSupabaseConfigured || !isUuid(auth.userId) || !conversations.value.some(item => item.id === conversationId)) return false
    const now = Date.now()
    const lastSent = lastTypingSentAt.get(conversationId) ?? 0
    if (isTyping && now - lastSent < 3000) return true
    lastTypingSentAt.set(conversationId, now)
    const { error } = await supabase.rpc('northstar_set_conversation_typing', {
      p_conversation_id: conversationId,
      p_is_typing: isTyping,
    })
    if (error) {
      typingError.value = `Typing indicators are unavailable: ${error.message}`
      if (!isTyping) lastTypingSentAt.delete(conversationId)
      return false
    }
    typingError.value = ''
    if (!isTyping) lastTypingSentAt.delete(conversationId)
    return true
  }

  async function refreshConversationTyping () {
    if (!supabase || !isSupabaseConfigured || !isUuid(useAuthStore().userId)) return
    const ids = conversations.value.map(conversation => conversation.id)
    if (!ids.length) return
    const { data, error } = await supabase.from('northstar_conversation_typing')
      .select('conversation_id,user_id,expires_at')
      .in('conversation_id', ids)
      .gt('expires_at', new Date().toISOString())
      .neq('user_id', useAuthStore().userId)
    if (error) {
      typingError.value = `Typing indicators are unavailable: ${error.message}`
      return
    }
    typingError.value = ''
    const active = new Map<string, string[]>()
    for (const row of data ?? []) {
      const users = active.get(row.conversation_id) ?? []
      users.push(row.user_id)
      active.set(row.conversation_id, users)
    }
    for (const conversation of conversations.value) conversation.typingUserIds = active.get(conversation.id) ?? []
  }

  async function markNotificationRead (id: string) {
    if (!isUuid(id) || !isUuid(useAuthStore().userId)) return
    const notification = notificationList.value.find(item => item.id === id)
    if (!notification) {
      return
    }
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Updating notifications requires a configured Northstar Supabase connection.'
      return
    }
    const { error } = await supabase.from('notifications').update({
      is_read: true,
      read_at: new Date().toISOString(),
    }).eq('id', id)
    if (error) {
      backendError.value = `Could not update notification: ${error.message}`
      console.error(backendError.value, error)
      return
    }
    notification.unread = false
  }

  async function markAllNotificationsRead () {
    if (!isUuid(useAuthStore().userId)) return
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Updating notifications requires a configured Northstar Supabase connection.'
      return
    }
    const { error } = await supabase.from('notifications').update({
      is_read: true,
      read_at: new Date().toISOString(),
    }).eq('user_id', useAuthStore().userId)
    if (error) {
      backendError.value = `Could not update notifications: ${error.message}`
      console.error(backendError.value, error)
      return
    }
    for (const item of notificationList.value) {
      item.unread = false
    }
  }

  async function deleteNotification (id: string) {
    if (!isUuid(id) || !isUuid(useAuthStore().userId)) return
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Managing notifications requires a configured Northstar Supabase connection.'
      return
    }
    const { error } = await supabase.from('notifications').delete().eq('id', id)
    if (error) {
      backendError.value = `Could not clear notification: ${error.message}`
      console.error(backendError.value, error)
      return
    }
    notificationList.value = notificationList.value.filter(item => item.id !== id)
  }

  async function toggleRsvp (id: string) {
    const auth = useAuthStore()
    if (!isUuid(id) || !isUuid(auth.userId)) return
    const event = eventList.value.find(item => item.id === id)
    if (!event) {
      return
    }
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Updating event RSVPs requires a configured Northstar Supabase connection.'
      return
    }
    const { error } = await supabase.from('event_attendees').upsert({
      event_id: id,
      user_id: auth.userId,
      attendance_status: event.attending ? 'declined' : 'going',
    }, { onConflict: 'event_id,user_id' })
    if (error) {
      backendError.value = `Could not update event RSVP: ${error.message}`
      console.error(backendError.value, error)
      return
    }
    event.attendees += event.attending ? -1 : 1
    event.attending = !event.attending
  }

  async function togglePinned (id: string) {
    const auth = useAuthStore()
    if (!auth.isAuthenticated || auth.isAdmin || auth.profile.role !== 'manager' || !auth.canAccessEmployeeWorkspace || !isUuid(id) || !isUuid(auth.userId)) {
      return
    }
    const announcement = announcementList.value.find(item => item.id === id)
    if (!announcement) {
      return
    }
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Updating announcements requires a configured Northstar Supabase connection.'
      return
    }
    const { error } = await supabase.from('announcements').update({ is_pinned: !announcement.pinned }).eq('id', id)
    if (error) {
      backendError.value = `Could not update announcement pin: ${error.message}`
      console.error(backendError.value, error)
      return
    }
    announcement.pinned = !announcement.pinned
  }

  async function publishAnnouncement (title: string, description: string, _author?: string) {
    const auth = useAuthStore()
    if (!auth.isAuthenticated || auth.isAdmin || auth.profile.role !== 'employee' || !auth.canAccessEmployeeWorkspace || !isUuid(auth.userId)) {
      backendError.value = 'Only active employee accounts can publish announcements.'
      return false
    }
    const trimmedTitle = title.trim()
    const trimmedDescription = description.trim()
    if (!trimmedTitle || !trimmedDescription) {
      return false
    }
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Publishing announcements requires a configured Northstar Supabase connection.'
      return false
    }
    const { data, error } = await supabase.from('announcements').insert({
      title: trimmedTitle,
      content: trimmedDescription,
      priority: 'normal',
      author_id: auth.userId,
    }).select('id,title,content,author_id,created_at,priority,is_pinned,author:profiles!announcements_author_id_fkey(first_name,last_name)').single()
    if (error) {
      backendError.value = `Could not publish announcement: ${error.message}`
      console.error(backendError.value, error)
      return false
    }
    announcementList.value.unshift({
      id: data.id,
      title: data.title,
      description: data.content,
      author: (() => {
        const creator = relationOne(data.author)
        return `${creator?.first_name ?? ''} ${creator?.last_name ?? ''}`.trim() || (data.author_id ? 'Name unavailable' : 'Creator not recorded')
      })(),
      department: 'Company',
      createdAt: data.created_at,
      priority: 'Normal',
      pinned: data.is_pinned,
    })
    return true
  }

  async function getResourceDownloadUrl (resource: Resource) {
    if (!resource.fileUrl || !isSupabaseConfigured || !supabase) {
      return ''
    }
    if (/^https?:\/\//i.test(resource.fileUrl)) {
      return resource.fileUrl
    }
    const { data, error } = await supabase.storage.from('company-resources').createSignedUrl(resource.fileUrl, 60)
    if (error) {
      backendError.value = `Could not create a resource download link: ${error.message}`
      console.error(backendError.value, error)
      return ''
    }
    return data.signedUrl
  }

  return {
    employees: employeeList,
    announcements: announcementList,
    conversations,
    notifications: notificationList,
    events: eventList,
    resources: resourceList,
    activityLogs,
    backendError,
    messageSyncError,
    receiptError,
    callHistoryError,
    presenceError,
    interactionError,
    conversationStateError,
    typingError,
    messageToast,
    dismissMessageToast: () => { messageToast.value = null },
    loading,
    load,
    loadAnnouncements,
    refreshConversations,
    subscribeToMessages,
    unsubscribeFromMessages,
    clearWorkspace,
    startConversation,
    departments,
    unreadNotifications,
    sendMessage,
    sendFirstMessage,
    acknowledgeMessageVisible,
    refreshMessageReceipts,
    refreshMessageInteractions,
    toggleMessageReaction,
    sendMessageAttachment,
    getMessageAttachmentUrl,
    editMessage,
    deleteMessageForEveryone,
    hideMessageForMe,
    markConversationRead,
    setConversationState,
    setMessagePinned,
    updateConversationTyping,
    refreshConversationTyping,
    markNotificationRead,
    markAllNotificationsRead,
    deleteNotification,
    toggleRsvp,
    togglePinned,
    publishAnnouncement,
    getResourceDownloadUrl,
  }
})

const avatarColors = ['#d9e9a6', '#f0d0c4', '#d4dfee', '#eadcb9', '#d5e8dc', '#e9d8ea']

function relationOne<T> (value: T | T[] | null | undefined): T | undefined {
  return Array.isArray(value) ? value[0] : value ?? undefined
}

async function messageRequestKey (userId: string, conversationId: string, content: string, replyToMessageId?: string) {
  const material = replyToMessageId
    ? `${userId}:${conversationId}\u0000${replyToMessageId}\u0000${content}`
    : `${userId}:${conversationId}\u0000${content}`
  if (globalThis.crypto?.subtle && typeof TextEncoder !== 'undefined') {
    const digest = await globalThis.crypto.subtle.digest('SHA-256', new TextEncoder().encode(material))
    const fingerprint = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('')
    return `northstar.pending:${userId}:${conversationId}:${fingerprint}`
  }
  return `memory:${material}`
}

async function attachmentRequestKey (userId: string, conversationId: string, file: File, caption: string, durationSeconds: number | null) {
  if (!globalThis.crypto?.subtle || typeof TextEncoder === 'undefined') {
    throw new Error('Secure attachment retry keys require a browser with Web Crypto support.')
  }
  const fileHash = await globalThis.crypto.subtle.digest('SHA-256', await file.arrayBuffer())
  const fingerprint = [...new Uint8Array(fileHash)].map(byte => byte.toString(16).padStart(2, '0')).join('')
  const material = `${userId}:${conversationId}:${file.name}:${file.type}:${file.size}:${fingerprint}:${caption.trim()}:${durationSeconds ?? ''}`
  const digest = await globalThis.crypto.subtle.digest('SHA-256', new TextEncoder().encode(material))
  const keyHash = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('')
  return `northstar.attachment:${userId}:${conversationId}:${keyHash}`
}

function sortByCreatedAt<T extends { created_at: string, id: string }> (rows: T[]): T[] {
  return rows.reduce<T[]>((sorted, row) => {
    const insertAt = sorted.findIndex(existing => compareChatMessages(existing, row) > 0)
    if (insertAt === -1) {
      sorted.push(row)
    } else {
      sorted.splice(insertAt, 0, row)
    }
    return sorted
  }, [])
}

function compareChatMessages (left: { created_at?: string, createdAt?: string, id: string }, right: { created_at?: string, createdAt?: string, id: string }) {
  const leftTime = Date.parse(left.created_at ?? left.createdAt ?? '')
  const rightTime = Date.parse(right.created_at ?? right.createdAt ?? '')
  return leftTime - rightTime || left.id.localeCompare(right.id)
}

function notificationCategory (type: string): WorkspaceNotification['category'] {
  if (type === 'message') {
    return 'Messages'
  }
  if (type === 'event') {
    return 'Events'
  }
  if (type === 'people') {
    return 'People'
  }
  return 'Announcements'
}

function notificationRoute (type: string, title = '', linkTo?: string | null) {
  if (linkTo?.startsWith('/') && !linkTo.startsWith('//')) {
    return linkTo
  }
  if (type === 'people' && title === 'Registration Approved') return '/overview'
  if (type === 'people' && title === 'Registration Update') return '/pending-approval'
  return ({
    message: '/messages',
    event: '/events',
    people: '/employees',
    resource: '/resources',
  } as Record<string, string>)[type] ?? '/announcements'
}

function isMissingNotificationLinkToColumn (error: { message: string, code?: string }) {
  const message = error.message.toLowerCase()
  return message.includes('link_to') && (
    error.code === '42703'
    || error.code === 'PGRST204'
    || message.includes('does not exist')
    || message.includes('schema cache')
  )
}
