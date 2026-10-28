import assert from 'node:assert/strict'
import test from 'node:test'
import { formatLastSeen, formatPresenceLabel } from '../presence.ts'

const now = Date.parse('2026-10-28T12:00:00.000Z')

test('reports online only when supplied by the presence result', () => {
  assert.equal(formatPresenceLabel(true, null, now), 'Online')
})

test('reports offline with a readable relative last-seen time', () => {
  assert.equal(formatPresenceLabel(false, '2026-10-28T11:55:00.000Z', now), 'Offline · Last seen 5 minutes ago')
})

test('uses a date and time for older last-seen values', () => {
  const timestamp = '2026-10-01T08:30:00.000Z'
  assert.equal(
    formatLastSeen(timestamp, now),
    `Last seen ${new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(Date.parse(timestamp))}`,
  )
})

test('keeps a missing record unavailable instead of inferring a status', () => {
  assert.equal(formatPresenceLabel(null, null, now), 'Status unavailable')
})
