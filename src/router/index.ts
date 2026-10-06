/**
 * router/index.ts
 *
 * Manual routes for ./src/pages/*.vue
 */

// Composables
import { createRouter, createWebHistory } from 'vue-router'
import AdminDashboard from '@/pages/adminDashboard.vue'
import Announcements from '@/pages/announcements.vue'
import Departments from '@/pages/departments.vue'
import DisasterManagement from '@/pages/disasterManagement.vue'
import EmployeeCommunication from '@/pages/employeeCommunication.vue'
import EmployeeDirectory from '@/pages/employeeDirectory.vue'
import Events from '@/pages/events.vue'
import Index from '@/pages/index.vue'
import Login from '@/pages/login.vue'
import Messages from '@/pages/messages.vue'
import Notifications from '@/pages/notifications.vue'
import Overview from '@/pages/overView.vue'
import PasswordReset from '@/pages/passwordReset.vue'
import Profile from '@/pages/profile.vue'
import Resources from '@/pages/resources.vue'
import Settings from '@/pages/settings.vue'
import StartConversation from '@/pages/startConversation.vue'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      component: Index,
    },
    {
      path: '/overview',
      component: Overview,
      meta: { requiresAuth: true },
    },
    {
      path: '/employees',
      component: EmployeeDirectory,
      meta: { requiresAuth: true },
    },
    {
      path: '/announcements',
      component: Announcements,
      meta: { requiresAuth: true },
    },
    {
      path: '/messages',
      component: Messages,
      meta: { requiresAuth: true },
    },
    {
      path: '/notifications',
      component: Notifications,
      meta: { requiresAuth: true },
    },
    {
      path: '/departments',
      component: Departments,
      meta: { requiresAuth: true },
    },
    {
      path: '/events',
      component: Events,
      meta: { requiresAuth: true },
    },
    {
      path: '/resources',
      component: Resources,
      meta: { requiresAuth: true },
    },
    {
      path: '/profile',
      component: Profile,
      meta: { requiresAuth: true },
    },
    {
      path: '/settings',
      component: Settings,
      meta: { requiresAuth: true },
    },
    {
      path: '/admin',
      component: AdminDashboard,
      meta: { requiresAuth: true, requiresAdmin: true },
    },
    {
      path: '/start-conversation',
      component: StartConversation,
      meta: { requiresAuth: true },
    },
    {
      path: '/employee-communication',
      component: EmployeeCommunication,
      meta: { requiresAuth: true },
    },
    {
      path: '/disaster-management',
      component: DisasterManagement,
      meta: { requiresAuth: true },
    },
    {
      path: '/login',
      component: Login,
    },
    {
      path: '/reset-password',
      component: PasswordReset,
      meta: { requiresPasswordRecovery: true },
    },
  ],
})

router.beforeEach(async to => {
  const auth = useAuthStore()
  await auth.initialize()

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return {
      path: '/login',
      query: { redirect: to.fullPath },
    }
  }

  if (to.meta.requiresAdmin && !auth.isAdmin) {
    return { path: '/overview' }
  }

  if (to.meta.requiresPasswordRecovery && !auth.isPasswordRecovery) {
    return { path: '/login' }
  }

  if (to.path === '/login' && auth.isAuthenticated) {
    return { path: typeof to.query.redirect === 'string' ? to.query.redirect : '/overview' }
  }
})

export default router
