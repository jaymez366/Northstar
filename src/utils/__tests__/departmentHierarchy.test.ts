import assert from 'node:assert/strict'
import test from 'node:test'
import { DEPARTMENT_RANKS, departmentRankLabel, isDepartmentCandidateEligible, isDepartmentRankAssignable, validateHeadReplacement } from '../departmentHierarchy.ts'

const eligibleCandidate = {
  department_id: 'department-a',
  role: 'employee',
  approval_status: 'approved',
  employment_status: 'active',
  registration_completed: true,
  email_verified: true,
}

test('department ranks are explicitly labelled Level 1 through Level 5', () => {
  assert.deepEqual(DEPARTMENT_RANKS.map(rank => rank.value), [1, 2, 3, 4, 5])
  assert.equal(departmentRankLabel(1), 'Level 1 — Department Head')
  assert.equal(departmentRankLabel(5), 'Level 5 — Entry-Level Department Member')
  assert.equal(departmentRankLabel(null), 'No rank assigned')
})

test('only registered, confirmed, approved, active employees and managers are appointable', () => {
  assert.equal(isDepartmentCandidateEligible(eligibleCandidate), true)
  assert.equal(isDepartmentRankAssignable({ ...eligibleCandidate, department_id: null }), true)
  for (const change of [
    { role: 'admin' },
    { approval_status: 'pending' },
    { employment_status: 'inactive' },
    { registration_completed: false },
    { email_verified: false },
    { department_id: null },
  ]) {
    assert.equal(isDepartmentCandidateEligible({ ...eligibleCandidate, ...change }), false)
  }
  assert.equal(isDepartmentCandidateEligible({ ...eligibleCandidate, role: 'manager' }), true)
  assert.equal(isDepartmentRankAssignable({ ...eligibleCandidate, role: 'manager' }), true)
})

test('head replacement requires a different proposed head and an explicit outgoing rank', () => {
  assert.equal(validateHeadReplacement(null, 'new-head', null), null)
  assert.match(validateHeadReplacement('old-head', 'new-head', null) ?? '', /Choose a replacement rank/)
  assert.match(validateHeadReplacement('old-head', 'new-head', 1) ?? '', /Level 2 to Level 5/)
  assert.equal(validateHeadReplacement('old-head', 'new-head', 3), null)
  assert.match(validateHeadReplacement('same-head', 'same-head', null) ?? '', /already the department head/)
  assert.match(validateHeadReplacement(null, null, null) ?? '', /Choose an eligible employee/)
})
