/**
 * router/index.ts
 *
 * Manual routes for ./src/pages/*.vue
 */

// Composables
import { createRouter, createWebHistory, type RouteLocationNormalized, type RouteLocationRaw } from 'vue-router'
import AdminDashboard from '@/pages/adminDashboard.vue'
import Announcements from '@/pages/announcements.vue'
import Departments from '@/pages/departments.vue'
import DisasterManagement from '@/pages/disasterManagement.vue'
import EmailVerification from '@/pages/emailVerification.vue'
import EmployeeCommunication from '@/pages/employeeCommunication.vue'
import EmployeeDirectory from '@/pages/employeeDirectory.vue'
import EmployeeRegistration from '@/pages/employeeRegistration.vue'
import Events from '@/pages/events.vue'
import Index from '@/pages/index.vue'
import Login from '@/pages/login.vue'
import Messages from '@/pages/messages.vue'
import Notifications from '@/pages/notifications.vue'
import Overview from '@/pages/overView.vue'
import PasswordReset from '@/pages/passwordReset.vue'
import PendingApproval from '@/pages/pendingApproval.vue'
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
    {
      path: '/verify-email',
      component: EmailVerification,
      meta: { allowUnverified: true },
    },
    {
      path: '/auth/callback',
      component: EmailVerification,
      meta: { authCallback: true },
    },
    {
      path: '/employee-registration',
      component: EmployeeRegistration,
      meta: { requiresAuth: true, allowIncompleteRegistration: true },
    },
    {
      path: '/pending-approval',
      component: PendingApproval,
      meta: { requiresAuth: true, allowPendingApproval: true },
    },
  ],
})

type AuthStore = ReturnType<typeof useAuthStore>

function getAuthenticationRedirect (to: RouteLocationNormalized, auth: AuthStore): RouteLocationRaw | undefined {
  if (to.meta.authCallback) {
    return
  }

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return {
      path: '/login',
      query: { redirect: to.fullPath },
    }
  }

  if (to.meta.allowUnverified && auth.isAuthenticated && auth.emailVerified) {
    return auth.profile.registrationCompleted
      ? (auth.profile.approvalStatus === 'approved' || auth.profile.role === 'admin' ? '/overview' : '/pending-approval')
      : '/employee-registration'
  }

  if (to.meta.requiresAuth && auth.isAuthenticated && !auth.emailVerified) {
    return { path: '/verify-email', query: { email: auth.userEmail } }
  }
}

function getRegistrationRedirect (to: RouteLocationNormalized, auth: AuthStore): RouteLocationRaw | undefined {
  if (
    to.meta.requiresAuth
    && auth.isAuthenticated
    && auth.emailVerified
    && !auth.profile.registrationCompleted
    && !to.meta.allowIncompleteRegistration
  ) {
    return '/employee-registration'
  }

  if (
    to.meta.requiresAuth
    && auth.isAuthenticated
    && auth.emailVerified
    && auth.profile.registrationCompleted
    && auth.profile.approvalStatus !== 'approved'
    && auth.profile.role !== 'admin'
    && !to.meta.allowPendingApproval
  ) {
    return '/pending-approval'
  }

  if (to.path === '/employee-registration' && auth.profile.registrationCompleted) {
    return auth.profile.approvalStatus === 'approved' || auth.profile.role === 'admin'
      ? '/overview'
      : '/pending-approval'
  }

  if (to.path === '/pending-approval' && auth.profile.approvalStatus === 'approved') {
    return '/overview'
  }
}

function getRoleRedirect (to: RouteLocationNormalized, auth: AuthStore): RouteLocationRaw | undefined {
  if (to.meta.requiresAdmin && !auth.isAdmin) {
    return auth.profile.approvalStatus === 'approved' ? { path: '/overview' } : { path: '/pending-approval' }
  }

  if (to.meta.requiresPasswordRecovery && !auth.isPasswordRecovery) {
    return { path: '/login' }
  }
}

function getLoginRedirect (to: RouteLocationNormalized, auth: AuthStore): RouteLocationRaw | undefined {
  if (to.path === '/login' && auth.isAuthenticated) {
    if (!auth.emailVerified) {
      return { path: '/verify-email', query: { email: auth.userEmail } }
    }
    if (!auth.profile.registrationCompleted) {
      return '/employee-registration'
    }
    if (auth.profile.approvalStatus !== 'approved' && auth.profile.role !== 'admin') {
      return '/pending-approval'
    }
    return { path: typeof to.query.redirect === 'string' ? to.query.redirect : '/overview' }
  }
}

router.beforeEach(async to => {
  const auth = useAuthStore()
  await auth.initialize()

  return getAuthenticationRedirect(to, auth)
    ?? getRegistrationRedirect(to, auth)
    ?? getRoleRedirect(to, auth)
    ?? getLoginRedirect(to, auth)
})

export default router
