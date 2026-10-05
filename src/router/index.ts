/**
 * router/index.ts
 *
 * Manual routes for ./src/pages/*.vue
 */

// Composables
import { createRouter, createWebHistory } from 'vue-router'
import DisasterManagement from '@/pages/disasterManagement.vue'
import EmployeeCommunication from '@/pages/employeeCommunication.vue'
import Index from '@/pages/index.vue'
import Login from '@/pages/login.vue'
import Overview from '@/pages/overView.vue'
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
  ],
})

router.beforeEach(to => {
  const auth = useAuthStore()

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return {
      path: '/login',
      query: { redirect: to.fullPath },
    }
  }

  if (to.path === '/login' && auth.isAuthenticated) {
    return { path: typeof to.query.redirect === 'string' ? to.query.redirect : '/overview' }
  }
})

export default router
