import { defineStore } from 'pinia'
import { ref } from 'vue'

const storageKey = 'northstar-authenticated'
const accountKey = 'northstar-account'

type Account = {
  email: string
  password: string
}

export const useAuthStore = defineStore('auth', () => {
  const isAuthenticated = ref(localStorage.getItem(storageKey) === 'true')
  const userEmail = ref(localStorage.getItem('northstar-user-email') ?? '')

  function login (email: string, password: string) {
    const savedAccount = localStorage.getItem(accountKey)
    const account = savedAccount ? JSON.parse(savedAccount) as Account : null
    const isDemoAccount = email === 'demo@northstar.com' && password === 'northstar123'
    const isSavedAccount = account?.email === email && account.password === password
    const isValid = isDemoAccount || isSavedAccount

    if (!isValid) {
      return false
    }

    isAuthenticated.value = true
    userEmail.value = email
    localStorage.setItem(storageKey, 'true')
    localStorage.setItem('northstar-user-email', email)
    return true
  }

  function signup (email: string, password: string) {
    localStorage.setItem(accountKey, JSON.stringify({ email, password }))
    isAuthenticated.value = true
    userEmail.value = email
    localStorage.setItem(storageKey, 'true')
    localStorage.setItem('northstar-user-email', email)
    return true
  }

  function logout () {
    isAuthenticated.value = false
    userEmail.value = ''
    localStorage.removeItem(storageKey)
    localStorage.removeItem('northstar-user-email')
  }

  return { isAuthenticated, userEmail, login, signup, logout }
})
