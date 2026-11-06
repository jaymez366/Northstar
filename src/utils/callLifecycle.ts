export type CallSessionStatus = 'ringing' | 'accepted' | 'declined' | 'cancelled' | 'missed' | 'ended' | 'failed'
export type CallSignalKind = 'offer' | 'answer' | 'ice'

export interface CallSignalIdentity {
  call_id: string
  sender_id: string
  recipient_id: string
  signal_type: CallSignalKind
}

export interface CallParticipants {
  id: string
  caller_id: string
  callee_id: string
}

export function isCallSessionActive (status: string, expiresAt: string, now = Date.now ()) {
  if (status === 'accepted') return true
  return status === 'ringing' && Number.isFinite(Date.parse(expiresAt)) && Date.parse(expiresAt) > now
}

export function invitationTimeRemaining (expiresAt: string, now = Date.now ()) {
  const expiry = Date.parse(expiresAt)
  return Number.isFinite(expiry) ? Math.max(0, expiry - now) : 0
}

export function isSignalForCallParticipant (
  signal: CallSignalIdentity,
  call: CallParticipants,
  userId: string,
) {
  if (signal.call_id !== call.id || ![call.caller_id, call.callee_id].includes(userId)) return false

  const otherParticipant = userId === call.caller_id ? call.callee_id : call.caller_id
  if (signal.sender_id !== otherParticipant || signal.recipient_id !== userId) return false

  if (signal.signal_type === 'offer') {
    return userId === call.callee_id && signal.sender_id === call.caller_id
  }
  if (signal.signal_type === 'answer') {
    return userId === call.caller_id && signal.sender_id === call.callee_id
  }
  return signal.signal_type === 'ice'
}

export function claimCallSignalId (signalId: string, handledSignalIds: Set<string>) {
  if (!signalId || handledSignalIds.has(signalId)) return false
  handledSignalIds.add(signalId)
  return true
}

export function reconnectDelayMs (attempt: number, maxAttempts = 6) {
  if (!Number.isInteger(attempt) || attempt < 1 || attempt > maxAttempts) return null
  return Math.min(500 * 2 ** (attempt - 1), 15_000)
}
