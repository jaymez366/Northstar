import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

const isUuid = (value: string | null | undefined): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)

export type Employee = {
  id: string
  firstName: string
  lastName: string
  title: string
  department: string
  email: string
  phone: string
  online: boolean | null
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
}

export type Conversation = {
  id: string
  employeeId: string
  name: string
  title: string
  initials: string
  color: string
  online: boolean | null
  unread: number
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
  const messageToast = ref<{ title: string, preview: string, conversationId: string, notificationId: string } | null>(null)
  const loading = ref(false)
  let realtimeChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null
  let notificationChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null
  let messageToastTimer: ReturnType<typeof setTimeout> | undefined
  let conversationRefreshPromise: Promise<string> | null = null
  const unreadNotifications = computed(() => notificationList.value.filter(item => item.unread).length)
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

    let notificationRows: Array<{
      id: string
      title: string
      message: string
      notification_type: string
      is_read: boolean
      created_at: string
      link_to?: string | null
    }> | null = null
    let notificationError: { message: string } | null = null
    const notificationQuery = await supabase
      .from('notifications')
      .select('id,title,message,notification_type,is_read,created_at,link_to')
      .eq('user_id', auth.userId)
      .order('created_at', { ascending: false })
    if (notificationQuery.error && isMissingNotificationLinkToColumn(notificationQuery.error)) {
      const fallbackQuery = await supabase
        .from('notifications')
        .select('id,title,message,notification_type,is_read,created_at')
        .eq('user_id', auth.userId)
        .order('created_at', { ascending: false })
      notificationRows = fallbackQuery.data
      notificationError = fallbackQuery.error
    } else {
      notificationRows = notificationQuery.data
      notificationError = notificationQuery.error
    }
    if (notificationError) {
      recordError('notifications', notificationError)
    } else {
      notificationList.value = (notificationRows ?? []).map(row => ({
        id: row.id,
        title: row.title,
        description: row.message,
        category: notificationCategory(row.notification_type),
        createdAt: new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(row.created_at)),
        unread: !row.is_read,
        to: notificationRoute(row.notification_type, row.title, row.link_to),
      }))
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
    realtimeChannel = supabase
      .channel(`northstar-messages-${useAuthStore().userId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, payload => {
        const message = payload.new as { id: string, conversation_id: string, sender_id: string, content: string, created_at: string }
        if (!isUuid(message.id) || !isUuid(message.conversation_id) || !isUuid(message.sender_id)) return
        const conversation = conversations.value.find(item => item.id === message.conversation_id)
        if (!conversation) {
          void refreshConversations()
          return
        }
        if (conversation.messages.some(item => item.id === message.id)) {
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
        })
        conversation.messages.sort(compareChatMessages)
        if (message.sender_id !== useAuthStore().userId) {
          conversation.unread += 1
        }
        conversation.updatedAt = 'Now'
        conversations.value.sort((a, b) => compareChatMessages(b.messages.at(-1) ?? { id: '', createdAt: '' }, a.messages.at(-1) ?? { id: '', createdAt: '' }))
      })
      .subscribe(status => {
        if (status === 'SUBSCRIBED') {
          messageSyncError.value = ''
          void refreshConversations()
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          messageSyncError.value = `Message updates are temporarily unavailable (${status}). Use Refresh messages to check for new activity.`
          backendError.value = `Supabase Realtime subscription failed: ${status}`
          console.error(backendError.value)
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
      .subscribe(status => {
        if (status === 'SUBSCRIBED') {
          void refreshConversations()
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          backendError.value = `Supabase notification subscription failed: ${status}`
          console.error(backendError.value)
        }
      })
  }

  function unsubscribeFromMessages () {
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
      return ''
    }
    const { data, error } = await supabase
      .from('conversations')
      .select('id,updated_at,conversation_members(user_id,last_read_at,profile:profiles!conversation_members_user_id_fkey(first_name,last_name,job_title,avatar_url)),messages(id,sender_id,content,created_at)')
      .in('id', ids)
      .order('updated_at', { ascending: false })
    if (error) return error.message

    conversations.value = (data ?? []).map(row => {
      const members = Array.isArray(row.conversation_members) ? row.conversation_members : []
      const peer = members.find((member: { user_id: string }) => member.user_id !== auth.userId)
      const ownMembership = members.find((member: { user_id: string }) => member.user_id === auth.userId)
      const profile = relationOne(peer?.profile)
      const firstName = profile?.first_name ?? 'Colleague'
      const lastName = profile?.last_name ?? ''
      const messages = sortByCreatedAt(Array.isArray(row.messages) ? row.messages : [])
      return {
        id: row.id,
        employeeId: peer?.user_id ?? '',
        name: `${firstName} ${lastName}`.trim(),
        title: profile?.job_title ?? '',
        initials: `${firstName[0] ?? ''}${lastName[0] ?? ''}`.toUpperCase(),
        color: '#dce8ba',
        online: null,
        unread: messages.filter((message: { sender_id: string, created_at: string }) => message.sender_id !== auth.userId && (!ownMembership?.last_read_at || message.created_at > ownMembership.last_read_at)).length,
        updatedAt: row.updated_at ? new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(row.updated_at)) : '',
        messages: messages.map((message: { id: string, sender_id: string, content: string, created_at: string }) => ({
          id: message.id,
          author: message.sender_id === auth.userId ? 'You' : `${firstName} ${lastName}`.trim(),
          text: message.content,
          sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(message.created_at)),
          createdAt: message.created_at,
          mine: message.sender_id === auth.userId,
        })),
      }
    }).filter(item => item.messages.length > 0)
    conversations.value.sort((a, b) => compareChatMessages(b.messages.at(-1) ?? { id: '', createdAt: '' }, a.messages.at(-1) ?? { id: '', createdAt: '' }))
    return ''
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
      return ''
    }
    return data
  }

  async function sendFirstMessage (employeeId: string, text: string) {
    const trimmed = text.trim()
    if (!trimmed) return false
    const id = await startConversation(employeeId)
    if (!id || !isSupabaseConfigured || !supabase) return false
    const { error } = await supabase.from('messages').insert({ conversation_id: id, content: trimmed })
    if (error) {
      backendError.value = `Could not send message: ${error.message}`
      console.error(backendError.value, error)
      return false
    }
    const refreshError = await refreshConversations()
    if (refreshError) backendError.value = `Message sent, but the conversation could not be refreshed: ${refreshError}`
    else backendError.value = ''
    return true
  }

  async function sendMessage (conversationId: string, text: string) {
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

    const { data, error } = await supabase.from('messages').insert({
      conversation_id: conversationId,
      content: trimmed,
    }).select('id,sender_id,content,created_at').single()
    if (error) {
      backendError.value = `Could not send message: ${error.message}`
      console.error(backendError.value, error)
      return false
    }
    if (!conversation.messages.some(item => item.id === data.id)) {
      conversation.messages.push({
        id: data.id,
        author: 'You',
        text: data.content,
        sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(data.created_at)),
        createdAt: data.created_at,
        mine: true,
      })
    }
    conversation.updatedAt = 'Now'
    conversations.value.sort((a, b) => compareChatMessages(b.messages.at(-1) ?? { id: '', createdAt: '' }, a.messages.at(-1) ?? { id: '', createdAt: '' }))
    backendError.value = ''
    return true
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
    const { error } = await supabase
      .from('conversation_members')
      .update({ last_read_at: new Date().toISOString() })
      .eq('conversation_id', conversationId)
      .eq('user_id', useAuthStore().userId)
    if (error) {
      backendError.value = `Could not mark messages as read: ${error.message}`
      console.error(backendError.value, error)
      return
    }
    conversation.unread = 0
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
    markConversationRead,
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
