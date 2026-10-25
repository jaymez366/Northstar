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
  online: boolean
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
  mine: boolean
}

export type Conversation = {
  id: string
  employeeId: string
  name: string
  title: string
  initials: string
  color: string
  online: boolean
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
  const loading = ref(false)
  let realtimeChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null
  let notificationChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null
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
        author: `${author?.first_name ?? ''} ${author?.last_name ?? ''}`.trim() || 'Northstar',
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
      employeeList.value = []
      announcementList.value = []
      conversations.value = []
      notificationList.value = []
      eventList.value = []
      resourceList.value = []
      departmentList.value = []
      activityLogs.value = []
      backendError.value = ''
      loading.value = false
      return
    }
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Northstar Supabase is not configured. Add the project URL and public key to the local environment before loading workspace data.'
      return
    }
    const client = supabase
    if (loading.value) return

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
          online: false,
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
          author: `${author?.first_name ?? ''} ${author?.last_name ?? ''}`.trim() || 'Northstar',
          department: department?.name ?? 'Company',
          createdAt: row.created_at,
          priority: ({ normal: 'Normal', important: 'High', urgent: 'High' } as const)[row.priority as 'normal' | 'important' | 'urgent'] ?? 'Normal',
          pinned: row.is_pinned,
        }
      })
    }

    const { data: notificationRows, error: notificationError } = await supabase
      .from('notifications')
      .select('id,title,message,notification_type,is_read,created_at,link_to')
      .eq('user_id', auth.userId)
      .order('created_at', { ascending: false })
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
        to: notificationRoute(row.notification_type, row.link_to),
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
          location: row.location ?? '',
          description: row.description ?? '',
          organizer: `${organizer?.first_name ?? ''} ${organizer?.last_name ?? ''}`.trim() || 'Northstar',
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

    const { data: memberships, error: membershipError } = await supabase
      .from('conversation_members')
      .select('conversation_id,last_read_at')
      .eq('user_id', auth.userId)
    if (membershipError) {
      recordError('conversation memberships', membershipError)
    } else {
      const conversationIds = [...new Set((memberships ?? []).map(row => row.conversation_id).filter(isUuid))]
      if (conversationIds.length === 0) {
        conversations.value = []
      } else {
        const { data: conversationRows, error: conversationError } = await supabase
          .from('conversations')
          .select('id,updated_at,conversation_members(user_id,last_read_at,profile:profiles!conversation_members_user_id_fkey(first_name,last_name,job_title,avatar_url)),messages!messages_conversation_id_fkey(id,sender_id,content,created_at)')
          .in('id', conversationIds)
          .order('updated_at', { ascending: false })
        if (conversationError) {
          recordError('conversations', conversationError)
        } else {
          conversations.value = (conversationRows ?? []).map(row => {
            const members = Array.isArray(row.conversation_members) ? row.conversation_members : []
            const peer = members.find((member: { user_id: string }) => member.user_id !== auth.userId)
            const ownMembership = members.find((member: { user_id: string }) => member.user_id === auth.userId)
            const peerProfile = relationOne(peer?.profile)
            const firstName = peerProfile?.first_name ?? 'Colleague'
            const lastName = peerProfile?.last_name ?? ''
            const messages = sortByCreatedAt(Array.isArray(row.messages) ? row.messages : [])
            return {
              id: row.id,
              employeeId: peer?.user_id ?? '',
              name: `${firstName} ${lastName}`.trim(),
              title: peerProfile?.job_title ?? '',
              initials: `${firstName[0] ?? ''}${lastName[0] ?? ''}`.toUpperCase(),
              color: '#dce8ba',
              online: false,
              unread: messages.filter((message: { sender_id: string, created_at: string }) => message.sender_id !== auth.userId && (!ownMembership?.last_read_at || message.created_at > ownMembership.last_read_at)).length,
              updatedAt: row.updated_at ? new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(row.updated_at)) : '',
              messages: messages.map((message: { id: string, sender_id: string, content: string, created_at: string }) => ({
                id: message.id,
                author: message.sender_id === auth.userId ? 'You' : `${firstName} ${lastName}`.trim(),
                text: message.content,
                sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(message.created_at)),
                mine: message.sender_id === auth.userId,
              })),
            }
          })
        }
      }
    }

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
    if (!isSupabaseConfigured || !supabase || !useAuthStore().userId || realtimeChannel) {
      return
    }
    realtimeChannel = supabase
      .channel(`northstar-messages-${useAuthStore().userId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, payload => {
        const message = payload.new as { id: string, conversation_id: string, sender_id: string, content: string, created_at: string }
        const conversation = conversations.value.find(item => item.id === message.conversation_id)
        if (!conversation || conversation.messages.some(item => item.id === message.id)) {
          return
        }
        const sender = employeeList.value.find(item => item.id === message.sender_id)
        conversation.messages.push({
          id: message.id,
          author: message.sender_id === useAuthStore().userId ? 'You' : (sender ? `${sender.firstName} ${sender.lastName}` : conversation.name),
          text: message.content,
          sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(message.created_at)),
          mine: message.sender_id === useAuthStore().userId,
        })
        if (message.sender_id !== useAuthStore().userId) {
          conversation.unread += 1
        }
        conversation.updatedAt = 'Now'
      })
      .subscribe(status => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
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
          link_to: string | null
        }
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
          to: notificationRoute(notification.notification_type, notification.link_to),
        })
      })
      .subscribe(status => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
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
  }

  async function startConversation (employeeId: string) {
    if (!isUuid(employeeId) || !isUuid(useAuthStore().userId) || employeeId === useAuthStore().userId) {
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
    const employee = employeeList.value.find(item => item.id === employeeId)
    if (!employee) {
      return ''
    }
    conversations.value.unshift({
      id: data,
      employeeId,
      name: `${employee.firstName} ${employee.lastName}`,
      title: employee.title,
      initials: employee.initials,
      color: employee.color,
      online: employee.online,
      unread: 0,
      updatedAt: 'Now',
      messages: [],
    })
    return data
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
        mine: true,
      })
    }
    conversation.updatedAt = 'Now'
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
    loading.value = false
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
    if (!isUuid(id) || !isUuid(useAuthStore().userId)) return
    const event = eventList.value.find(item => item.id === id)
    if (!event) {
      return
    }
    if (!isSupabaseConfigured || !supabase) {
      backendError.value = 'Updating event RSVPs requires a configured Northstar Supabase connection.'
      return
    }
    const auth = useAuthStore()
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
    if (auth.isAdmin || auth.profile.role !== 'manager' || !isUuid(id) || !isUuid(auth.userId)) return
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

  async function publishAnnouncement (title: string, description: string, author: string) {
    const auth = useAuthStore()
    if (auth.isAdmin || auth.profile.role !== 'employee' || !auth.canAccessEmployeeWorkspace) return false
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
    }).select('id,title,content,created_at,priority,is_pinned').single()
    if (error) {
      backendError.value = `Could not publish announcement: ${error.message}`
      console.error(backendError.value, error)
      return false
    }
    announcementList.value.unshift({
      id: data.id,
      title: data.title,
      description: data.content,
      author,
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
    loadAnnouncements,
    conversations,
    notifications: notificationList,
    events: eventList,
    resources: resourceList,
    activityLogs,
    backendError,
    loading,
    load,
    clearWorkspace,
    subscribeToMessages,
    unsubscribeFromMessages,
    startConversation,
    departments,
    unreadNotifications,
    sendMessage,
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

function sortByCreatedAt<T extends { created_at: string }> (rows: T[]): T[] {
  return rows.reduce<T[]>((sorted, row) => {
    const insertAt = sorted.findIndex(existing => Date.parse(existing.created_at) > Date.parse(row.created_at))
    if (insertAt === -1) {
      sorted.push(row)
    } else {
      sorted.splice(insertAt, 0, row)
    }
    return sorted
  }, [])
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

function notificationRoute (type: string, linkTo?: string | null) {
  if (linkTo?.startsWith('/') && !linkTo.startsWith('//')) {
    return linkTo
  }
  return ({
    message: '/messages',
    event: '/events',
    people: '/employees',
    resource: '/resources',
  } as Record<string, string>)[type] ?? '/announcements'
}
