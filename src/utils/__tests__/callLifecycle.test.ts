import assert from 'node:assert/strict'
import test from 'node:test'
import {
  claimCallSignalId,
  invitationTimeRemaining,
  isCallSessionActive,
  isSignalForCallParticipant,
  reconnectDelayMs,
} from '../callLifecycle.ts'

const call = {
  id: '11111111-1111-4111-8111-111111111111',
  caller_id: '22222222-2222-4222-8222-222222222222',
  callee_id: '33333333-3333-4333-8333-333333333333',
}

test('ringing invitations expire at their deadline while accepted calls remain active', () => {
  const past = new Date(1_000).toISOString()
  const future = new Date(2_000).toISOString()

  assert.equal(isCallSessionActive('ringing', past, 1_500), false)
  assert.equal(isCallSessionActive('ringing', future, 1_500), true)
  assert.equal(isCallSessionActive('accepted', past, 1_500), true)
  assert.equal(isCallSessionActive('ended', future, 1_500), false)
})

test('invitation timeout is bounded by the server expiry timestamp', () => {
  assert.equal(invitationTimeRemaining(new Date(5_000).toISOString(), 2_000), 3_000)
  assert.equal(invitationTimeRemaining(new Date(1_000).toISOString(), 2_000), 0)
  assert.equal(invitationTimeRemaining('invalid', 2_000), 0)
})

test('offer, answer, and ICE signals are accepted only from the other call participant in the correct role', () => {
  const signal = (signal_type: 'offer' | 'answer' | 'ice', sender_id: string, recipient_id: string) => ({
    call_id: call.id, signal_type, sender_id, recipient_id,
  })

  assert.equal(isSignalForCallParticipant(signal('offer', call.caller_id, call.callee_id), call, call.callee_id), true)
  assert.equal(isSignalForCallParticipant(signal('answer', call.callee_id, call.caller_id), call, call.caller_id), true)
  assert.equal(isSignalForCallParticipant(signal('ice', call.callee_id, call.caller_id), call, call.caller_id), true)
  assert.equal(isSignalForCallParticipant(signal('offer', call.caller_id, call.caller_id), call, call.caller_id), false)
  assert.equal(isSignalForCallParticipant(signal('answer', call.caller_id, call.callee_id), call, call.callee_id), false)
  assert.equal(isSignalForCallParticipant(signal('ice', call.caller_id, call.callee_id), call, '44444444-4444-4444-8444-444444444444'), false)
  assert.equal(isSignalForCallParticipant({ ...signal('ice', call.caller_id, call.callee_id), call_id: 'other' }, call, call.callee_id), false)
})

test('duplicate signaling events are claimed once', () => {
  const handled = new Set<string>()
  assert.equal(claimCallSignalId('signal-1', handled), true)
  assert.equal(claimCallSignalId('signal-1', handled), false)
  assert.equal(claimCallSignalId('', handled), false)
})

test('Realtime retry delay is exponential and bounded', () => {
  assert.deepEqual([1, 2, 3, 4, 5, 6].map(attempt => reconnectDelayMs(attempt)), [500, 1_000, 2_000, 4_000, 8_000, 15_000])
  assert.equal(reconnectDelayMs(0), null)
  assert.equal(reconnectDelayMs(7), null)
})
