/**
 * router/index.ts
 *
 * Manual routes for ./src/pages/*.vue
 */

// Composables
import { createRouter, createWebHistory, type RouteLocationNormalized, type RouteLocationRaw } from 'vue-router'
import AdminDashboard from '@/pages/adminDashboard.vue'
import AdminLogin from '@/pages/adminLogin.vue'
import AdminEvents from '@/pages/adminEvents.vue'
import AdminResources from '@/pages/adminResources.vue'
import AdminDepartments from '@/pages/adminDepartments.vue'
import DepartmentCollaboration from '@/pages/departmentCollaboration.vue'
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
import RegistrationHistory from '@/pages/registrationHistory.vue'
import Resources from '@/pages/resources.vue'
import Settings from '@/pages/settings.vue'
import StartConversation from '@/pages/startConversation.vue'
import SupportInquiries from '@/pages/supportInquiries.vue'
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
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/employees',
      component: EmployeeDirectory,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/announcements',
      component: Announcements,
      meta: { requiresAuth: true, adminReadable: true },
    },
    {
      path: '/messages',
      component: Messages,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/notifications',
      component: Notifications,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/departments',
      component: Departments,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/department',
      component: DepartmentCollaboration,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true, allowDesignatedAdmin: true },
    },
    {
      path: '/events',
      component: Events,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/resources',
      component: Resources,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/profile',
      component: Profile,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/settings',
      component: Settings,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/admin',
      component: AdminDashboard,
      meta: { requiresAuth: true, requiresAdmin: true },
    },
    {
      path: '/admin/events',
      component: AdminEvents,
      meta: { requiresAuth: true, requiresAdmin: true },
    },
    {
      path: '/admin/resources',
      component: AdminResources,
      meta: { requiresAuth: true, requiresAdmin: true },
    },
    {
      path: '/admin/departments',
      component: AdminDepartments,
      meta: { requiresAuth: true, requiresAdmin: true },
    },
    {
      path: '/admin-login',
      component: AdminLogin,
    },
    {
      path: '/start-conversation',
      component: StartConversation,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/support-inquiries',
      component: SupportInquiries,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/employee-communication',
      component: EmployeeCommunication,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true },
    },
    {
      path: '/disaster-management',
      component: DisasterManagement,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true, allowDesignatedAdmin: true, adminReadable: true },
    },
    {
      path: '/login',
      component: Login,
    },
    {
      path: '/reset-password',
      component: PasswordReset,
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
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true, allowIncompleteRegistration: true },
    },
    {
      path: '/pending-approval',
      component: PendingApproval,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true, allowPendingApproval: true },
    },
    {
      path: '/rejection-history',
      component: RegistrationHistory,
      meta: { requiresAuth: true, requiresEmployeeWorkspace: true, allowPendingApproval: true },
    },
  ],
})

const landingMetadata = {
  title: 'NorthStar | B2B Employee Communication Platform',
  description: 'NorthStar is a B2B employee communication platform for clear team updates and coordinated responses during critical moments.',
  url: 'https://northstar-1k1.pages.dev/',
}

function setHeadEntry (selector: string, tagName: 'meta' | 'link', attributes: Record<string, string> | null) {
  let element = document.head.querySelector<HTMLMetaElement | HTMLLinkElement>(selector)
  if (!attributes) {
    element?.remove()
    return
  }
  if (!element) {
    element = document.createElement(tagName)
    document.head.append(element)
  }
  for (const [name, value] of Object.entries(attributes)) element.setAttribute(name, value)
}

router.afterEach(to => {
  const isLandingPage = to.path === '/'
  document.title = isLandingPage ? landingMetadata.title : 'NorthStar | Employee Workspace'

  setHeadEntry('meta[name="description"]', 'meta', isLandingPage
    ? { name: 'description', content: landingMetadata.description }
    : null)
  setHeadEntry('link[rel="canonical"]', 'link', isLandingPage
    ? { rel: 'canonical', href: landingMetadata.url }
    : null)
  for (const [property, content] of Object.entries({
    'og:type': 'website',
    'og:site_name': 'NorthStar',
    'og:title': landingMetadata.title,
    'og:description': landingMetadata.description,
    'og:url': landingMetadata.url,
  })) {
    setHeadEntry(`meta[property="${property}"]`, 'meta', isLandingPage ? { property, content } : null)
  }
  for (const [name, content] of Object.entries({
    'twitter:card': 'summary',
    'twitter:title': landingMetadata.title,
    'twitter:description': landingMetadata.description,
  })) {
    setHeadEntry(`meta[name="${name}"]`, 'meta', isLandingPage ? { name, content } : null)
  }

  const schema = document.getElementById('northstar-website-schema')
  if (isLandingPage && !schema) {
    const script = document.createElement('script')
    script.id = 'northstar-website-schema'
    script.type = 'application/ld+json'
    script.textContent = JSON.stringify({
      '@context': 'https://schema.org',
      '@type': 'WebSite',
      name: 'NorthStar',
      url: landingMetadata.url,
      description: landingMetadata.description,
    })
    document.head.append(script)
  } else if (!isLandingPage) {
    schema?.remove()
  }
  setHeadEntry('meta[name="robots"]', 'meta', isLandingPage ? null : { name: 'robots', content: 'noindex, nofollow' })
})

type AuthStore = ReturnType<typeof useAuthStore>

function requiresEmployeeProfile (to: RouteLocationNormalized, auth: AuthStore) {
  return to.meta.requiresAuth && auth.isAuthenticated && auth.emailVerified && !auth.isAdmin
}

function needsProfileLoad (to: RouteLocationNormalized, auth: AuthStore) {
  return requiresEmployeeProfile(to, auth)
    && !auth.profileLoaded
    && !to.meta.allowIncompleteRegistration
}

function needsRegistration (to: RouteLocationNormalized, auth: AuthStore) {
  return requiresEmployeeProfile(to, auth)
    && auth.profileLoaded
    && !auth.employeeRegistrationComplete
    && !to.meta.allowIncompleteRegistration
}

function awaitsApproval (to: RouteLocationNormalized, auth: AuthStore) {
  return requiresEmployeeProfile(to, auth)
    && auth.employeeRegistrationComplete
    && auth.profile.approvalStatus !== 'rejected'
    && !auth.canAccessEmployeeWorkspace
    && !to.meta.allowPendingApproval
}

function hasRejectedRegistration (to: RouteLocationNormalized, auth: AuthStore) {
  return requiresEmployeeProfile(to, auth)
    && auth.employeeRegistrationComplete
    && auth.profile.approvalStatus === 'rejected'
    && !to.meta.allowPendingApproval
    && !to.meta.allowIncompleteRegistration
}

function getAuthenticationRedirect (to: RouteLocationNormalized, auth: AuthStore): RouteLocationRaw | undefined {
  if (to.meta.authCallback) {
    return
  }

  if (to.meta.requiresAdmin && !auth.isAuthenticated) {
    return {
      path: '/admin-login',
      query: { redirect: '/admin' },
    }
  }

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return {
      path: '/login',
      query: { redirect: to.fullPath },
    }
  }

  if (to.meta.requiresEmployeeWorkspace && auth.isAdmin && !to.meta.allowDesignatedAdmin) {
    return '/admin'
  }

  if (to.meta.allowUnverified && auth.isAuthenticated && auth.emailVerified) {
    return auth.employeeRegistrationComplete
      ? (auth.canAccessEmployeeWorkspace ? '/overview' : '/pending-approval')
      : '/employee-registration'
  }

  if (to.meta.requiresAuth && auth.isAuthenticated && !auth.emailVerified) {
    return { path: '/verify-email', query: { email: auth.userEmail } }
  }
}

function getRegistrationRedirect (to: RouteLocationNormalized, auth: AuthStore): RouteLocationRaw | undefined {
  if (needsProfileLoad(to, auth)) {
    return { path: '/login', query: { profileError: 'true' } }
  }

  if (needsRegistration(to, auth)) {
    return '/employee-registration'
  }

  if (awaitsApproval(to, auth)) {
    return '/pending-approval'
  }

  if (hasRejectedRegistration(to, auth)) {
    return '/pending-approval'
  }

  if (
    to.path === '/employee-registration'
    && auth.employeeRegistrationComplete
    && auth.profile.approvalStatus !== 'rejected'
  ) {
    return auth.profile.approvalStatus === 'approved' || auth.isAdmin
      ? '/overview'
      : '/pending-approval'
  }

  if (to.path === '/pending-approval' && auth.profile.approvalStatus === 'approved') {
    return auth.canAccessEmployeeWorkspace ? '/overview' : undefined
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
    if (auth.isAdmin) {
      return { path: typeof to.query.redirect === 'string' ? to.query.redirect : '/admin' }
    }
    if (!auth.profileLoaded) {
      return
    }
    if (!auth.employeeRegistrationComplete) {
      return '/employee-registration'
    }
    if (!auth.canAccessEmployeeWorkspace) {
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
