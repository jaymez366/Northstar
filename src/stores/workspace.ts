import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'

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

const employees: Employee[] = [
  { id: 'e1', firstName: 'Jordan', lastName: 'Lee', title: 'People Operations Lead', department: 'People', email: 'jordan.lee@northstar.com', phone: '+1 (415) 555-0101', online: true, initials: 'JL', color: '#d9e9a6' },
  { id: 'e2', firstName: 'Maya', lastName: 'Patel', title: 'Internal Communications Manager', department: 'Communications', email: 'maya.patel@northstar.com', phone: '+1 (415) 555-0102', online: true, initials: 'MP', color: '#f0d0c4' },
  { id: 'e3', firstName: 'Theo', lastName: 'Brooks', title: 'Director of Engineering', department: 'Engineering', email: 'theo.brooks@northstar.com', phone: '+1 (415) 555-0103', online: false, initials: 'TB', color: '#d4dfee' },
  { id: 'e4', firstName: 'Ava', lastName: 'Kim', title: 'Finance Partner', department: 'Finance', email: 'ava.kim@northstar.com', phone: '+1 (415) 555-0104', online: true, initials: 'AK', color: '#eadcb9' },
  { id: 'e5', firstName: 'Noah', lastName: 'Garcia', title: 'Workplace Experience Lead', department: 'Operations', email: 'noah.garcia@northstar.com', phone: '+1 (415) 555-0105', online: false, initials: 'NG', color: '#d5e8dc' },
  { id: 'e6', firstName: 'Priya', lastName: 'Shah', title: 'Customer Success Director', department: 'Customer Success', email: 'priya.shah@northstar.com', phone: '+1 (415) 555-0106', online: true, initials: 'PS', color: '#e9d8ea' },
  { id: 'e7', firstName: 'Ethan', lastName: 'Wright', title: 'Security Program Manager', department: 'Security', email: 'ethan.wright@northstar.com', phone: '+1 (415) 555-0107', online: false, initials: 'EW', color: '#d8e6ed' },
  { id: 'e8', firstName: 'Sofia', lastName: 'Martin', title: 'Brand Designer', department: 'Communications', email: 'sofia.martin@northstar.com', phone: '+1 (415) 555-0108', online: true, initials: 'SM', color: '#f1dfd5' },
]

const announcements: Announcement[] = [
  { id: 'a1', title: 'Company town hall: October edition', description: 'Join us for our monthly company update. We’ll share progress on this quarter’s priorities and leave plenty of time for your questions.', author: 'Maya Patel', department: 'Communications', createdAt: '2026-10-05T09:30:00', priority: 'High', pinned: true },
  { id: 'a2', title: 'Open enrollment begins next week', description: 'Review your benefits options and make your selections before the enrollment window closes on October 23.', author: 'Jordan Lee', department: 'People', createdAt: '2026-10-04T14:15:00', priority: 'High', pinned: true },
  { id: 'a3', title: 'New focus rooms on the third floor', description: 'Four quiet focus rooms are now available to book through the workplace calendar. Please leave each room ready for the next person.', author: 'Noah Garcia', department: 'Operations', createdAt: '2026-10-03T11:00:00', priority: 'Normal', pinned: false },
  { id: 'a4', title: 'October product release notes', description: 'The latest release includes improved notification preferences, faster search, and a refreshed mobile experience.', author: 'Theo Brooks', department: 'Engineering', createdAt: '2026-10-02T16:45:00', priority: 'Normal', pinned: false },
  { id: 'a5', title: 'Volunteer afternoon sign-ups are open', description: 'Spend an afternoon with the team supporting our neighborhood food bank. Sign up by Friday to reserve your place.', author: 'Priya Shah', department: 'Customer Success', createdAt: '2026-10-01T10:20:00', priority: 'Low', pinned: false },
]

const initialConversations: Conversation[] = [
  { id: 'c1', employeeId: 'e2', name: 'Maya Patel', title: 'Internal Communications Manager', initials: 'MP', color: '#f0d0c4', online: true, unread: 2, updatedAt: '9:41 AM', messages: [{ id: '1', author: 'Maya Patel', text: 'Hi! I’m pulling together the town hall agenda.', sentAt: '9:36 AM', mine: false }, { id: '2', author: 'You', text: 'Great — I can send over a few talking points.', sentAt: '9:38 AM', mine: true }, { id: '3', author: 'Maya Patel', text: 'That would be wonderful. Could you send them before lunch?', sentAt: '9:41 AM', mine: false }] },
  { id: 'c2', employeeId: 'e1', name: 'Jordan Lee', title: 'People Operations Lead', initials: 'JL', color: '#d9e9a6', online: true, unread: 0, updatedAt: 'Yesterday', messages: [{ id: '1', author: 'Jordan Lee', text: 'Thanks for reviewing the benefits guide!', sentAt: 'Yesterday', mine: false }] },
  { id: 'c3', employeeId: 'e3', name: 'Theo Brooks', title: 'Director of Engineering', initials: 'TB', color: '#d4dfee', online: false, unread: 0, updatedAt: 'Monday', messages: [{ id: '1', author: 'You', text: 'The release notes look great.', sentAt: 'Monday', mine: true }] },
  { id: 'c4', employeeId: 'e5', name: 'Noah Garcia', title: 'Workplace Experience Lead', initials: 'NG', color: '#d5e8dc', online: false, unread: 1, updatedAt: 'Oct 2', messages: [{ id: '1', author: 'Noah Garcia', text: 'The new rooms are ready to book.', sentAt: 'Oct 2', mine: false }] },
]

const initialNotifications: WorkspaceNotification[] = [
  { id: 'n1', title: 'Town hall agenda posted', description: 'Maya Patel shared the October town hall details.', category: 'Announcements', createdAt: '10 minutes ago', unread: true, to: '/announcements' },
  { id: 'n2', title: 'New message from Maya Patel', description: 'Could you send them before lunch?', category: 'Messages', createdAt: '24 minutes ago', unread: true, to: '/messages' },
  { id: 'n3', title: 'Designing for clarity workshop', description: 'Your event starts tomorrow at 10:00 AM.', category: 'Events', createdAt: '1 hour ago', unread: true, to: '/events' },
  { id: 'n4', title: 'Welcome Sofia Martin', description: 'Sofia joined the Communications department.', category: 'People', createdAt: 'Yesterday', unread: false, to: '/employees' },
  { id: 'n5', title: 'Benefits guide updated', description: 'The 2026 employee benefits guide is ready to review.', category: 'Announcements', createdAt: 'Yesterday', unread: false, to: '/resources' },
]

const events: CompanyEvent[] = [
  { id: 'ev1', title: 'Designing for clarity workshop', startsAt: '2026-10-07T10:00:00', location: 'Studio 2 · 3rd floor', description: 'A practical, hands-on session on writing updates people can understand and act on.', organizer: 'Maya Patel', attendees: 28, attending: true },
  { id: 'ev2', title: 'October company town hall', startsAt: '2026-10-09T13:00:00', location: 'All hands · Main auditorium', description: 'Monthly company update, team highlights, and an open Q&A with leadership.', organizer: 'Jordan Lee', attendees: 146, attending: false },
  { id: 'ev3', title: 'New manager roundtable', startsAt: '2026-10-14T11:30:00', location: 'Conference room North', description: 'Connect with fellow managers and share approaches for building healthy teams.', organizer: 'People team', attendees: 16, attending: false },
  { id: 'ev4', title: 'Community volunteer afternoon', startsAt: '2026-10-17T13:30:00', location: 'Harbor Food Bank', description: 'Join colleagues for an afternoon supporting our local food bank.', organizer: 'Priya Shah', attendees: 34, attending: true },
]

const resources: Resource[] = [
  { id: 'r1', title: 'Employee handbook', category: 'Policies', description: 'How we work, what we value, and the practical policies that support every Northstar teammate.', format: 'PDF · 2.4 MB', updatedAt: 'Updated Sep 28, 2026' },
  { id: 'r2', title: '2026 benefits guide', category: 'People', description: 'A guide to healthcare, retirement, leave, and the benefits available to your household.', format: 'PDF · 1.8 MB', updatedAt: 'Updated Oct 5, 2026' },
  { id: 'r3', title: 'Incident response playbook', category: 'Operations', description: 'Roles, escalation paths, and communication templates for a coordinated response.', format: 'PDF · 3.1 MB', updatedAt: 'Updated Sep 20, 2026' },
  { id: 'r4', title: 'Manager essentials', category: 'Training', description: 'Core resources for supporting your team through growth, change, and everyday work.', format: 'Course · 6 lessons', updatedAt: 'Updated Sep 18, 2026' },
  { id: 'r5', title: 'Expense reimbursement form', category: 'Forms', description: 'Submit a business expense for review and reimbursement.', format: 'XLSX · 84 KB', updatedAt: 'Updated Aug 30, 2026' },
  { id: 'r6', title: 'Brand and communications guide', category: 'Communications', description: 'Voice, visual identity, and practical guidance for clear company communications.', format: 'PDF · 4.2 MB', updatedAt: 'Updated Aug 14, 2026' },
  { id: 'r7', title: 'Security awareness essentials', category: 'Training', description: 'Quick lessons for protecting company information and spotting common threats.', format: 'Course · 4 lessons', updatedAt: 'Updated Aug 8, 2026' },
]

export const useWorkspaceStore = defineStore('workspace', () => {
  const employeeList = ref(employees)
  const announcementList = ref(announcements)
  const conversations = ref<Conversation[]>(loadStored('northstar-conversations', initialConversations))
  const notificationList = ref<WorkspaceNotification[]>(loadStored('northstar-notifications', initialNotifications))
  const eventList = ref<CompanyEvent[]>(loadStored('northstar-events', events))
  const resourceList = ref(resources)
  const departmentList = ref<{ id: string, name: string, description: string }[]>([])
  const activityLogs = ref<{ id: string, action: string, description: string, createdAt: string, user: string }[]>([])
  const backendError = ref('')
  const loading = ref(false)
  let realtimeChannel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null
  const unreadNotifications = computed(() => notificationList.value.filter(item => item.unread).length)
  const departments = computed(() => {
    const departmentNames = departmentList.value.length > 0
      ? departmentList.value.map(department => department.name)
      : [...new Set(employeeList.value.map(employee => employee.department))]
    return departmentNames.map(name => ({
      name,
      count: employeeList.value.filter(employee => employee.department === name).length,
      description: departmentList.value.find(department => department.name === name)?.description
        ?? departmentDescriptions[name]
        ?? 'Working together to help Northstar move forward.',
      members: employeeList.value.filter(employee => employee.department === name),
    }))
  })

  async function load () {
    if (!isSupabaseConfigured || !supabase) {
      return
    }
    const client = supabase
    const auth = useAuthStore()
    if (!auth.userId || loading.value) {
      return
    }

    loading.value = true
    backendError.value = ''
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
      .select('id,first_name,last_name,email,avatar_url,job_title,department_id,phone,status,departments(name)')
      .eq('status', 'active')
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
          phone: row.phone ?? '',
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
      .select('id,title,message,type,is_read,created_at')
      .eq('user_id', auth.userId)
      .order('created_at', { ascending: false })
    if (notificationError) {
      recordError('notifications', notificationError)
    } else {
      notificationList.value = (notificationRows ?? []).map(row => ({
        id: row.id,
        title: row.title,
        description: row.message,
        category: notificationCategory(row.type),
        createdAt: new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(row.created_at)),
        unread: !row.is_read,
        to: notificationRoute(row.type),
      }))
    }

    const { data: eventRows, error: eventError } = await supabase
      .from('events')
      .select('id,title,description,location,start_time,end_time,organizer:profiles!events_organizer_id_fkey(first_name,last_name),event_attendees(user_id,status)')
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
          attendees: attendees.filter((attendee: { status: string }) => attendee.status === 'going').length,
          attending: ownRsvp?.status === 'going',
        }
      })
    }

    const { data: resourceRows, error: resourceError } = await supabase
      .from('resources')
      .select('id,title,description,file_url,category,created_at,updated_at')
      .order('updated_at', { ascending: false })
    if (resourceError) {
      recordError('resources', resourceError)
    } else {
      resourceList.value = (resourceRows ?? []).map(row => ({
        id: row.id,
        title: row.title,
        category: row.category,
        description: row.description ?? '',
        format: row.file_url?.split('.').at(-1)?.toUpperCase() ?? 'DOCUMENT',
        updatedAt: `Updated ${new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(row.updated_at ?? row.created_at))}`,
        fileUrl: row.file_url ?? '',
      }))
    }

    const { data: memberships, error: membershipError } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('user_id', auth.userId)
    if (membershipError) {
      recordError('conversation memberships', membershipError)
    } else {
      const conversationIds = [...new Set((memberships ?? []).map(row => row.conversation_id))]
      if (conversationIds.length === 0) {
        conversations.value = []
      } else {
        const { data: conversationRows, error: conversationError } = await supabase
          .from('conversations')
          .select('id,updated_at,conversation_members(user_id,profile:profiles!conversation_members_user_id_fkey(first_name,last_name,job_title,avatar_url)),messages(id,sender_id,content,is_read,created_at)')
          .in('id', conversationIds)
          .order('updated_at', { ascending: false })
        if (conversationError) {
          recordError('conversations', conversationError)
        } else {
          conversations.value = (conversationRows ?? []).map(row => {
            const members = Array.isArray(row.conversation_members) ? row.conversation_members : []
            const peer = members.find((member: { user_id: string }) => member.user_id !== auth.userId)
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
              unread: messages.filter((message: { sender_id: string, is_read: boolean }) => message.sender_id !== auth.userId && !message.is_read).length,
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
  }

  function unsubscribeFromMessages () {
    if (realtimeChannel && supabase) {
      void supabase.removeChannel(realtimeChannel)
    }
    realtimeChannel = null
  }

  async function startConversation (employeeId: string) {
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
    const conversation = conversations.value.find(item => item.id === conversationId)
    const trimmed = text.trim()
    if (!conversation || !trimmed) {
      return false
    }

    if (isSupabaseConfigured && supabase) {
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

    conversation.messages.push({
      id: String(Date.now()),
      author: 'You',
      text: trimmed,
      sentAt: new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date()),
      mine: true,
    })
    conversation.updatedAt = 'Now'
    persist('northstar-conversations', conversations.value)
    return true
  }

  async function markConversationRead (conversationId: string) {
    const conversation = conversations.value.find(item => item.id === conversationId)
    if (!conversation) {
      return
    }
    conversation.unread = 0
    if (isSupabaseConfigured && supabase) {
      const auth = useAuthStore()
      const { error } = await supabase.from('messages').update({ is_read: true }).eq('conversation_id', conversationId).neq('sender_id', auth.userId)
      if (error) {
        backendError.value = `Could not mark messages as read: ${error.message}`
        console.error(backendError.value, error)
      }
    } else {
      persist('northstar-conversations', conversations.value)
    }
  }

  async function markNotificationRead (id: string) {
    const notification = notificationList.value.find(item => item.id === id)
    if (!notification) {
      return
    }
    if (isSupabaseConfigured && supabase) {
      const { error } = await supabase.from('notifications').update({ is_read: true }).eq('id', id)
      if (error) {
        backendError.value = `Could not update notification: ${error.message}`
        console.error(backendError.value, error)
        return
      }
    }
    notification.unread = false
    if (!isSupabaseConfigured) {
      persist('northstar-notifications', notificationList.value)
    }
  }

  async function markAllNotificationsRead () {
    if (isSupabaseConfigured && supabase) {
      const { error } = await supabase.from('notifications').update({ is_read: true }).eq('user_id', useAuthStore().userId)
      if (error) {
        backendError.value = `Could not update notifications: ${error.message}`
        console.error(backendError.value, error)
        return
      }
    }
    for (const item of notificationList.value) {
      item.unread = false
    }
    if (!isSupabaseConfigured) {
      persist('northstar-notifications', notificationList.value)
    }
  }

  async function deleteNotification (id: string) {
    if (isSupabaseConfigured && supabase) {
      const { error } = await supabase.from('notifications').delete().eq('id', id)
      if (error) {
        backendError.value = `Could not clear notification: ${error.message}`
        console.error(backendError.value, error)
        return
      }
    }
    notificationList.value = notificationList.value.filter(item => item.id !== id)
    if (!isSupabaseConfigured) {
      persist('northstar-notifications', notificationList.value)
    }
  }

  async function toggleRsvp (id: string) {
    const event = eventList.value.find(item => item.id === id)
    if (!event) {
      return
    }
    if (isSupabaseConfigured && supabase) {
      const auth = useAuthStore()
      const status = event.attending ? 'declined' : 'going'
      const { error } = await supabase.from('event_attendees').upsert({
        event_id: id,
        user_id: auth.userId,
        status,
      }, { onConflict: 'event_id,user_id' })
      if (error) {
        backendError.value = `Could not update event RSVP: ${error.message}`
        console.error(backendError.value, error)
        return
      }
    }
    event.attendees += event.attending ? -1 : 1
    event.attending = !event.attending
    if (!isSupabaseConfigured) {
      persist('northstar-events', eventList.value)
    }
  }

  async function togglePinned (id: string) {
    const announcement = announcementList.value.find(item => item.id === id)
    if (!announcement) {
      return
    }
    if (isSupabaseConfigured && supabase) {
      const { error } = await supabase.from('announcements').update({ is_pinned: !announcement.pinned }).eq('id', id)
      if (error) {
        backendError.value = `Could not update announcement pin: ${error.message}`
        console.error(backendError.value, error)
        return
      }
    }
    announcement.pinned = !announcement.pinned
  }

  async function publishAnnouncement (title: string, description: string, author: string) {
    const trimmedTitle = title.trim()
    const trimmedDescription = description.trim()
    if (!trimmedTitle || !trimmedDescription) {
      return false
    }
    if (isSupabaseConfigured && supabase) {
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

    announcementList.value.unshift({
      id: `a-${Date.now()}`,
      title: trimmedTitle,
      description: trimmedDescription,
      author,
      department: 'Company',
      createdAt: new Date().toISOString(),
      priority: 'Normal',
      pinned: false,
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
    loading,
    load,
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

function notificationRoute (type: string) {
  return ({
    message: '/messages',
    event: '/events',
    people: '/employees',
    resource: '/resources',
  } as Record<string, string>)[type] ?? '/announcements'
}

const departmentDescriptions: Record<string, string> = {
  'People': 'Helping every teammate do their best work and feel supported.',
  'Communications': 'Making sure the right information reaches the right people.',
  'Engineering': 'Building reliable, thoughtful tools for our customers and teams.',
  'Finance': 'Creating clarity and confidence around our financial decisions.',
  'Operations': 'Making the day-to-day work of Northstar run smoothly.',
  'Customer Success': 'Helping customers get meaningful outcomes from Northstar.',
  'Security': 'Protecting our people, systems, and customer trust.',
}

function loadStored<T> (key: string, fallback: T): T {
  const stored = localStorage.getItem(key)
  return stored ? JSON.parse(stored) as T : fallback
}

function persist (key: string, value: unknown) {
  localStorage.setItem(key, JSON.stringify(value))
}
