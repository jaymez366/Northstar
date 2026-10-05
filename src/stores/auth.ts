import { defineStore } from 'pinia'
import { ref } from 'vue'

const storageKey = 'northstar-authenticated'
const accountKey = 'northstar-account'

type Account = {
  email: string
  password: string
  firstName?: string
}

export const useAuthStore = defineStore('auth', () => {
  const isAuthenticated = ref(localStorage.getItem(storageKey) === 'true')
  const userEmail = ref(localStorage.getItem('northstar-user-email') ?? '')
  const userFirstName = ref(localStorage.getItem('northstar-user-first-name') ?? '')

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
    if (account?.email === email && account.firstName) {
      userFirstName.value = account.firstName
    } else if (isDemoAccount) {
      userFirstName.value = 'Demo'
    } else {
      userFirstName.value = email.split('@', 1)[0]
    }
    localStorage.setItem(storageKey, 'true')
    localStorage.setItem('northstar-user-email', email)
    localStorage.setItem('northstar-user-first-name', userFirstName.value)
    return true
  }

  function signup (email: string, password: string, firstName: string) {
    localStorage.setItem(accountKey, JSON.stringify({ email, password, firstName }))
    isAuthenticated.value = true
    userEmail.value = email
    userFirstName.value = firstName
    localStorage.setItem(storageKey, 'true')
    localStorage.setItem('northstar-user-email', email)
    localStorage.setItem('northstar-user-first-name', firstName)
    return true
  }

  function logout () {
    isAuthenticated.value = false
    userEmail.value = ''
    userFirstName.value = ''
    localStorage.removeItem(storageKey)
    localStorage.removeItem('northstar-user-email')
    localStorage.removeItem('northstar-user-first-name')
  }

  return { isAuthenticated, userEmail, userFirstName, login, signup, logout }
})
