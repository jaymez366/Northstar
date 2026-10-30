export const DEPARTMENT_RANKS = [
  { value: 1, label: 'Level 1 — Department Head' },
  { value: 2, label: 'Level 2 — Senior Department Member' },
  { value: 3, label: 'Level 3 — Department Member' },
  { value: 4, label: 'Level 4 — Junior Department Member' },
  { value: 5, label: 'Level 5 — Entry-Level Department Member' },
] as const

export type DepartmentCandidateEligibility = {
  department_id: string | null
  role: string | null
  approval_status: string | null
  employment_status: string | null
  registration_completed: boolean | null
  email_verified: boolean | null
}

export function isDepartmentCandidateEligible (candidate: DepartmentCandidateEligibility) {
  return Boolean(candidate.department_id) && isDepartmentRankAssignable(candidate)
}

export function isDepartmentRankAssignable (candidate: DepartmentCandidateEligibility) {
  return (candidate.role === 'employee' || candidate.role === 'manager')
    && candidate.approval_status === 'approved'
    && candidate.employment_status === 'active'
    && candidate.registration_completed === true
    && candidate.email_verified === true
}

export function departmentRankLabel (level: number | null | undefined) {
  return DEPARTMENT_RANKS.find(rank => rank.value === level)?.label ?? 'No rank assigned'
}

export function validateHeadReplacement (currentHeadId: string | null, proposedHeadId: string | null, outgoingLevel: number | null) {
  if (!proposedHeadId) return 'Choose an eligible employee.'
  if (currentHeadId === proposedHeadId) return 'The selected employee is already the department head.'
  if (currentHeadId && (!Number.isInteger(outgoingLevel) || outgoingLevel! < 2 || outgoingLevel! > 5)) {
    return 'Choose a replacement rank from Level 2 to Level 5 for the current head.'
  }
  if (!currentHeadId && outgoingLevel !== null) return 'There is no current head to replace.'
  return null
}
