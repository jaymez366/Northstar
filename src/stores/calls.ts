import { computed, ref, watch } from 'vue'
import { defineStore } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured, supabase } from '../../lib/supabase.js'
import {
  claimCallSignalId,
  invitationTimeRemaining,
  isCallSessionActive,
  isSignalForCallParticipant,
  reconnectDelayMs,
} from '@/utils/callLifecycle'

type CallKind = 'audio' | 'video'
type CallStatus = 'starting' | 'calling' | 'ringing' | 'connecting' | 'connected' | 'disconnected'
type CallRow = {
  id: string
  conversation_id: string
  caller_id: string
  callee_id: string
  call_type: CallKind
  status: string
  expires_at: string
}
type CallSignal = {
  id: string
  call_id: string
  sender_id: string
  recipient_id: string
  signal_type: 'offer' | 'answer' | 'ice'
  payload: Record<string, unknown>
}
type CallAction = 'accept' | 'decline' | 'cancel' | 'missed' | 'end' | 'failed' | 'heartbeat'
type ActiveCall = CallRow & { status: CallStatus }

const expectedStatusByAction: Record<CallAction, string> = {
  accept: 'accepted',
  decline: 'declined',
  cancel: 'cancelled',
  missed: 'missed',
  end: 'ended',
  failed: 'failed',
  heartbeat: 'accepted',
}
const terminalStatuses = new Set(['declined', 'cancelled', 'missed', 'ended', 'failed'])
const knownServerStatuses = new Set(['ringing', 'accepted', ...terminalStatuses])

const isUuid = (value: unknown): value is string => typeof value === 'string'
  && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)

export const useCallsStore = defineStore('northstar-calls', () => {
  const activeCall = ref<ActiveCall | null>(null)
  const incomingCall = ref<CallRow | null>(null)
  const localStream = ref<MediaStream | null>(null)
  const remoteStream = ref<MediaStream | null>(null)
  const muted = ref(false)
  const cameraEnabled = ref(true)
  const screenSharing = ref(false)
  const error = ref('')
  const notice = ref('')
  const isInCall = computed(() => Boolean(activeCall.value))
  const callStartInFlight = ref(false)
  const incomingActionInFlight = ref(false)
  const signalingReady = ref(false)
  const minimized = ref(false)
  const connectedDurationSeconds = ref(0)
  let channel: ReturnType<NonNullable<typeof supabase>['channel']> | null = null
  let channelGeneration = 0
  let listening = false
  let reconnectAttempts = 0
  let browserEventsBound = false
  let browserWasOffline = false
  let peer: RTCPeerConnection | null = null
  let screenStream: MediaStream | null = null
  let screenVideoSender: RTCRtpSender | null = null
  let ringTimer: ReturnType<typeof setTimeout> | undefined
  let incomingTimer: ReturnType<typeof setTimeout> | undefined
  let reconnectTimer: ReturnType<typeof setTimeout> | undefined
  let stableSubscriptionTimer: ReturnType<typeof setTimeout> | undefined
  let terminalRetryTimer: ReturnType<typeof setTimeout> | undefined
  let leaseTimer: ReturnType<typeof setInterval> | undefined
  let disconnectTimer: ReturnType<typeof setTimeout> | undefined
  let durationTimer: ReturnType<typeof setInterval> | undefined
  let connectedAt: number | null = null
  let signalQueue = Promise.resolve()
  let heartbeatInFlight = false
  let hasSubscribed = false
  let subscriptionInterrupted = false
  let realtimeUnavailable = false
  let recoveryInFlight = false
  let startGeneration = 0
  const handledSignalIds = new Set<string>()
  const pendingTerminalActions = new Map<string, {
    action: Exclude<CallAction, 'heartbeat'>,
    call: CallRow,
    attempts: number,
  }>()
  const terminalRetryInFlight = new Set<string>()
  let queuedIce: RTCIceCandidateInit[] = []

  watch(() => useAuthStore().userId, (userId, previousUserId) => {
    if (userId === previousUserId) return
    if (previousUserId) {
      void stopListening(false).finally(() => {
        if (isUuid(userId)) startListening()
      })
    } else if (isUuid(userId)) startListening()
  })

  function clearSubscriptionError () {
    if (error.value.startsWith('Supabase Realtime reported ')) error.value = ''
  }

  function clearReconnectTimers () {
    if (reconnectTimer) clearTimeout(reconnectTimer)
    if (stableSubscriptionTimer) clearTimeout(stableSubscriptionTimer)
    reconnectTimer = undefined
    stableSubscriptionTimer = undefined
  }

  function retireChannel (candidate: NonNullable<typeof channel>, generation: number, remove = true) {
    if (channel !== candidate || channelGeneration !== generation) return false
    channel = null
    channelGeneration += 1
    if (remove && supabase) void supabase.removeChannel(candidate).catch(() => {})
    return true
  }

  function scheduleReconnect (immediate = false) {
    if (!listening || channel || reconnectTimer || !supabase) return
    if (typeof navigator !== 'undefined' && !navigator.onLine) return
    if (typeof document !== 'undefined' && document.visibilityState !== 'visible') return
    const delay = reconnectDelayMs(reconnectAttempts + 1)
    if (delay === null) {
      error.value = 'Call signaling could not reconnect. Try again when your connection is stable.'
      return
    }
    reconnectAttempts += 1
    reconnectTimer = setTimeout(() => {
      reconnectTimer = undefined
      startListening()
    }, immediate ? 0 : delay)
  }

  function handleBrowserOffline () {
    if (!listening) return
    browserWasOffline = true
    signalingReady.value = false
    subscriptionInterrupted = true
    realtimeUnavailable = true
    const current = channel
    if (current) retireChannel(current, channelGeneration)
  }

  function handleBrowserOnline () {
    if (!listening) return
    if (browserWasOffline) {
      reconnectAttempts = 0
      browserWasOffline = false
    }
    scheduleReconnect(true)
  }

  function handleDocumentVisibility () {
    if (!listening || document.visibilityState !== 'visible' || !navigator.onLine) return
    if (signalingReady.value) {
      void recoverCallState()
      return
    }
    if (channel) retireChannel(channel, channelGeneration)
    scheduleReconnect(true)
  }

  function bindBrowserEvents () {
    if (browserEventsBound || typeof window === 'undefined' || typeof document === 'undefined') return
    window.addEventListener('offline', handleBrowserOffline)
    window.addEventListener('online', handleBrowserOnline)
    document.addEventListener('visibilitychange', handleDocumentVisibility)
    browserEventsBound = true
  }

  function unbindBrowserEvents () {
    if (!browserEventsBound || typeof window === 'undefined' || typeof document === 'undefined') return
    window.removeEventListener('offline', handleBrowserOffline)
    window.removeEventListener('online', handleBrowserOnline)
    document.removeEventListener('visibilitychange', handleDocumentVisibility)
    browserEventsBound = false
  }

  function startListening () {
    const auth = useAuthStore()
    if (!supabase || !isSupabaseConfigured || !isUuid(auth.userId) || channel) return
    listening = true
    bindBrowserEvents()
    if (reconnectTimer) clearTimeout(reconnectTimer)
    reconnectTimer = undefined
    const subscribedChannel = supabase.channel(`northstar-call-signals-${auth.userId}`, {
      config: { postgres_changes_options: { wait: true } },
    })
    const generation = ++channelGeneration
    channel = subscribedChannel
    const isCurrentSubscription = () => listening && channel === subscribedChannel && channelGeneration === generation
    const retryAfterFailure = (status: string, removeChannel = true) => {
      if (!isCurrentSubscription()) return
      signalingReady.value = false
      subscriptionInterrupted = true
      realtimeUnavailable = true
      error.value = `Supabase Realtime reported ${status} for call signaling. Reconnecting automatically.`
      if (stableSubscriptionTimer) clearTimeout(stableSubscriptionTimer)
      stableSubscriptionTimer = undefined
      if (retireChannel(subscribedChannel, generation, removeChannel)) scheduleReconnect()
    }
    subscribedChannel
      .on('postgres_changes', { event: '*', schema: 'public', table: 'northstar_call_sessions' }, payload => {
        if (!isCurrentSubscription()) return
        handleSessionChange((payload.new ?? payload.old) as CallRow | undefined)
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'northstar_call_signals' }, payload => {
        if (!isCurrentSubscription()) return
        const signal = payload.new as Partial<CallSignal> | null
        if (!signal || !isUuid(signal.id) || !isUuid(signal.call_id) || !isUuid(signal.sender_id)
            || signal.recipient_id !== auth.userId || !['offer', 'answer', 'ice'].includes(signal.signal_type ?? '')
            || !signal.payload || typeof signal.payload !== 'object' || Array.isArray(signal.payload)) return
        queueSignal(signal as CallSignal)
      })
      .subscribe((status) => {
        if (!isCurrentSubscription()) return
        if (status === 'SUBSCRIBED') {
          signalingReady.value = true
          clearSubscriptionError()
          if (reconnectTimer) clearTimeout(reconnectTimer)
          reconnectTimer = undefined
          if (stableSubscriptionTimer) clearTimeout(stableSubscriptionTimer)
          stableSubscriptionTimer = setTimeout(() => {
            if (isCurrentSubscription()) reconnectAttempts = 0
            stableSubscriptionTimer = undefined
          }, 30_000)
          const reconnect = hasSubscribed || subscriptionInterrupted
          hasSubscribed = true
          subscriptionInterrupted = false
          if (reconnect) void recoverCallState()
          else {
            realtimeUnavailable = false
            void loadPendingInvitation()
            void retryPendingTerminalActions()
          }
        }
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          retryAfterFailure(status)
        } else if (status === 'CLOSED') {
          retryAfterFailure(status, false)
        }
      })
  }

  function handleSessionChange (row?: CallRow) {
    if (!row || !isUuid(row.id)) return
    const userId = useAuthStore().userId
    if (row.callee_id === userId && row.status === 'ringing' && Date.parse(row.expires_at) > Date.now() && !activeCall.value) {
      incomingCall.value = row
      startIncomingExpiry(row)
      return
    }
    if (incomingCall.value?.id === row.id && ['declined', 'cancelled', 'missed', 'ended', 'failed'].includes(row.status)) {
      clearIncomingTimer()
      incomingCall.value = null
      notice.value = row.status === 'cancelled' ? 'The caller cancelled the invitation.' : 'The call invitation is no longer available.'
    } else if (incomingCall.value?.id === row.id && row.status === 'accepted') {
      clearIncomingTimer()
      incomingCall.value = null
      notice.value = 'This invitation was accepted on another session.'
    }
    if (activeCall.value?.id !== row.id) return
    if (row.status === 'accepted') {
      if (activeCall.value.status !== 'connected' && activeCall.value.status !== 'disconnected') {
        activeCall.value.status = 'connecting'
      }
      clearRingTimer()
      startLeaseHeartbeat()
    } else if (['declined', 'cancelled', 'missed', 'ended', 'failed'].includes(row.status)) {
      notice.value = row.status === 'declined' ? 'The call was declined.'
        : row.status === 'missed' ? 'The call was not answered.'
          : row.status === 'failed' ? 'The call could not connect.'
            : row.status === 'ended' ? 'The call ended.' : 'The call was cancelled.'
      releaseCallResources()
    }
  }

  async function loadPendingInvitation () {
    const userId = useAuthStore().userId
    if (!supabase || !isUuid(userId) || activeCall.value || incomingCall.value) return
    const { data, error: queryError } = await supabase.from('northstar_call_sessions')
      .select('id,conversation_id,caller_id,callee_id,call_type,status,expires_at')
      .eq('callee_id', userId)
      .eq('status', 'ringing')
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
    if (queryError) {
      error.value = `Could not check for incoming calls: ${queryError.message}`
      return
    }
    const row = normalizeRow(data?.[0])
    if (row) handleSessionChange(row)
  }

  function startIncomingExpiry (row: CallRow) {
    clearIncomingTimer()
    incomingTimer = setTimeout(() => {
      if (incomingCall.value?.id === row.id) incomingCall.value = null
      incomingTimer = undefined
    }, Math.max(0, Date.parse(row.expires_at) - Date.now()))
  }

  function clearIncomingTimer () {
    if (incomingTimer) clearTimeout(incomingTimer)
    incomingTimer = undefined
  }

  async function startCall (conversationId: string, callType: CallKind) {
    if (callStartInFlight.value) {
      error.value = 'A call is already being prepared. Please wait.'
      return false
    }
    if (activeCall.value || incomingCall.value) {
      error.value = 'Finish the current call invitation before starting another call.'
      return false
    }
    if (!supabase || !isSupabaseConfigured || !isUuid(conversationId)) {
      error.value = 'Secure call signaling is not configured.'
      return false
    }
    if (!signalingReady.value) {
      error.value = 'Call signaling is not connected yet. Wait for the secure connection and try again.'
      return false
    }
    error.value = ''
    notice.value = ''
    callStartInFlight.value = true
    const generation = ++startGeneration
    let startFailed = false
    try {
      const configuration = await getRtcConfiguration()
      if (generation !== startGeneration) return false
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: callType === 'video' })
      if (generation !== startGeneration) {
        stream.getTracks().forEach(track => track.stop())
        return false
      }
      localStream.value = stream
      if (activeCall.value || incomingCall.value) {
        releaseMedia()
        error.value = 'Another call invitation arrived while media access was being prepared.'
        return false
      }

      const { data, error: rpcError } = await supabase.rpc('northstar_start_call', {
        p_conversation_id: conversationId,
        p_call_type: callType,
      })
      if (rpcError) throw new Error(`Could not start call: ${rpcError.message}`)
      const row = normalizeRow(data)
      if (!row || !isUuid(row.id) || row.conversation_id !== conversationId || row.caller_id !== useAuthStore().userId
          || row.call_type !== callType || !isUuid(row.callee_id)) {
        throw new Error('Call signaling returned an invalid or unexpected session. No call was started.')
      }
      if (generation !== startGeneration) {
        const cleanupAction = row.status === 'ringing' ? 'cancel' : row.status === 'accepted' ? 'end' : null
        if (cleanupAction) void supabase.rpc('northstar_update_call_status', { p_call_id: row.id, p_action: cleanupAction })
        releaseMedia()
        return false
      }
      if (row.status !== 'ringing') {
        if (row.status === 'accepted') void supabase.rpc('northstar_update_call_status', { p_call_id: row.id, p_action: 'end' })
        throw new Error('Call signaling returned an unexpected state. No local call was started.')
      }

      activeCall.value = { ...row, status: 'calling' }
      await createPeerConnection(configuration)
      const offer = await peer!.createOffer()
      await peer!.setLocalDescription(offer)
      await sendSignal(row.id, 'offer', { type: offer.type, sdp: offer.sdp })
      setRingTimeout(row.id, row.expires_at)
      if (!configuration.iceServers?.some(server => (Array.isArray(server.urls) ? server.urls : [server.urls]).some(url => url.startsWith('turn:') || url.startsWith('turns:')))) {
        notice.value = 'No TURN server is configured. Calls may fail on restrictive networks.'
      }
      return true
    } catch (reason) {
      startFailed = true
      error.value = reason instanceof Error ? reason.message : 'The call could not be prepared.'
      return false
    } finally {
      if (startFailed && activeCall.value) {
        const callId = activeCall.value.id
        if (activeCall.value.status === 'calling' || activeCall.value.status === 'ringing') {
          const call = activeCall.value
          void changeCallStatus(callId, 'failed').then(success => {
            if (!success) rememberTerminalAction(call, 'failed')
          })
        }
        releaseCallResources()
      } else if (startFailed) {
        releaseMedia()
      }
      if (generation === startGeneration) callStartInFlight.value = false
    }
  }

  async function acceptIncomingCall () {
    const row = incomingCall.value
    if (!row || activeCall.value || !supabase || incomingActionInFlight.value) return false
    if (!signalingReady.value) {
      error.value = 'Call signaling is temporarily unavailable. You can try accepting again when it reconnects.'
      return false
    }
    error.value = ''
    incomingActionInFlight.value = true
    try {
      let configuration: RTCConfiguration
      try {
        configuration = await getRtcConfiguration()
        localStream.value = await navigator.mediaDevices.getUserMedia({ audio: true, video: row.call_type === 'video' })
      } catch (reason) {
        releaseMedia()
        error.value = reason instanceof Error ? reason.message : 'Could not access the microphone or camera.'
        return false
      }

      activeCall.value = { ...row, status: 'starting' }
      incomingCall.value = null
      clearIncomingTimer()
      const accepted = await changeCallStatus(row.id, 'accept')
      if (!accepted) {
        const canRetry = activeCall.value?.id === row.id && row.status === 'ringing'
        releaseCallResources()
        if (canRetry && Date.parse(row.expires_at) > Date.now()) {
          incomingCall.value = row
          startIncomingExpiry(row)
        }
        return false
      }
      if (activeCall.value?.id !== row.id) {
        error.value = 'The call ended before the connection could be prepared.'
        releaseCallResources()
        return false
      }
      activeCall.value.status = 'connecting'
      try {
        await createPeerConnection(configuration)
        startLeaseHeartbeat()
        const { data, error: readError } = await supabase.from('northstar_call_signals')
          .select('id,call_id,sender_id,recipient_id,signal_type,payload')
          .eq('call_id', row.id)
          .order('created_at', { ascending: true })
          .order('id', { ascending: true })
        if (readError) throw new Error(`Could not load private call signaling: ${readError.message}`)
        if (!await confirmCallStillActive(row.id, 'accepted')) {
          releaseCallResources()
          return false
        }
        for (const signal of (data ?? []) as CallSignal[]) queueSignal(signal)
        return true
      } catch (reason) {
        await changeCallStatus(row.id, 'failed')
        if (activeCall.value?.id === row.id) rememberTerminalAction(activeCall.value, 'failed')
        releaseCallResources()
        error.value = reason instanceof Error ? reason.message : 'The call could not be accepted.'
        return false
      }
    } finally {
      incomingActionInFlight.value = false
    }
  }

  async function declineIncomingCall () {
    const row = incomingCall.value
    if (!row || incomingActionInFlight.value) return false
    incomingActionInFlight.value = true
    try {
      const success = await changeCallStatus(row.id, 'decline')
      if (success) {
        clearIncomingTimer()
        incomingCall.value = null
      } else rememberTerminalAction(row, 'decline')
      return success
    } finally {
      incomingActionInFlight.value = false
    }
  }

  async function endCall () {
    const row = activeCall.value
    if (!row) return false
    const action = row.status === 'calling' || row.status === 'ringing' ? 'cancel' : 'end'
    const success = await changeCallStatus(row.id, action)
    if (!success) rememberTerminalAction(row, action)
    releaseCallResources()
    return success
  }

  async function toggleMute () {
    const tracks = localStream.value?.getAudioTracks() ?? []
    if (!tracks.length) return false
    muted.value = !muted.value
    tracks.forEach(track => { track.enabled = !muted.value })
    return true
  }

  async function toggleCamera () {
    const tracks = localStream.value?.getVideoTracks() ?? []
    if (!tracks.length) return false
    if (cameraEnabled.value && screenSharing.value) await stopScreenSharing()
    cameraEnabled.value = !cameraEnabled.value
    tracks.forEach(track => { track.enabled = cameraEnabled.value })
    return true
  }

  async function toggleScreenSharing () {
    if (screenSharing.value) {
      await stopScreenSharing()
      return true
    }
    const call = activeCall.value
    const cameraTrack = localStream.value?.getVideoTracks().find(track => track.readyState === 'live')
    if (!navigator.mediaDevices?.getDisplayMedia || !call || call.call_type !== 'video'
        || call.status !== 'connected' || !cameraEnabled.value || !cameraTrack?.enabled || !peer) {
      error.value = 'Screen sharing requires a connected video call with your camera enabled.'
      return false
    }
    const sender = peer.getSenders().find(candidate => candidate.track?.kind === 'video')
    if (!sender) {
      error.value = 'Screen sharing is unavailable because this call has no active video sender.'
      return false
    }
    const currentPeer = peer
    let displayStream: MediaStream | null = null
    try {
      displayStream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false })
      const displayTrack = displayStream.getVideoTracks()[0]
      if (!displayTrack || activeCall.value?.id !== call.id || peer?.connectionState !== 'connected'
          || !cameraTrack.enabled || cameraTrack.readyState !== 'live') {
        displayStream.getTracks().forEach(track => track.stop())
        error.value = 'The call changed before screen sharing could start.'
        return false
      }
      await sender.replaceTrack(displayTrack)
      if (activeCall.value?.id !== call.id || peer !== currentPeer || currentPeer.connectionState !== 'connected') {
        try {
          if (peer === currentPeer) await sender.replaceTrack(cameraTrack)
        } catch {
          // The peer connection may already be closed by the terminal call cleanup.
        }
        displayStream.getTracks().forEach(track => track.stop())
        error.value = 'The call ended before screen sharing could start.'
        return false
      }
      screenStream = displayStream
      screenVideoSender = sender
      screenSharing.value = true
      error.value = ''
      displayTrack.onended = () => { void stopScreenSharing() }
      return true
    } catch (reason) {
      displayStream?.getTracks().forEach(track => track.stop())
      error.value = reason instanceof Error
        ? `Could not start screen sharing: ${reason.message}`
        : 'Could not start screen sharing. Check browser permission and try again.'
      return false
    }
  }

  async function stopScreenSharing () {
    const stream = screenStream
    const sender = screenVideoSender
    const cameraTrack = localStream.value?.getVideoTracks().find(track => track.readyState === 'live')
    const displayTrack = stream?.getVideoTracks()[0]
    if (displayTrack) displayTrack.onended = null
    screenStream = null
    screenVideoSender = null
    screenSharing.value = false
    try {
      if (sender && peer && cameraTrack && activeCall.value) await sender.replaceTrack(cameraTrack)
      else if (sender && peer && activeCall.value) await sender.replaceTrack(null)
    } catch {
      if (activeCall.value) error.value = 'Screen sharing stopped, but the camera track could not be restored. End and restart the video call.'
    } finally {
      stream?.getTracks().forEach(track => track.stop())
    }
  }

  async function createPeerConnection (configuration: RTCConfiguration) {
    if (!localStream.value || !activeCall.value) throw new Error('Call media is not ready.')
    peer?.close()
    peer = new RTCPeerConnection(configuration)
    remoteStream.value = new MediaStream()
    for (const track of localStream.value.getTracks()) peer.addTrack(track, localStream.value)
    peer.ontrack = event => {
      const stream = remoteStream.value
      if (stream && !stream.getTracks().some(track => track.id === event.track.id)) stream.addTrack(event.track)
    }
    peer.onicecandidate = event => {
      if (event.candidate && activeCall.value) {
        void sendSignal(activeCall.value.id, 'ice', { ...event.candidate.toJSON() }).catch(failCall)
      }
    }
    peer.onconnectionstatechange = () => {
      if (!peer || !activeCall.value) return
      if (peer.connectionState === 'connected') {
        activeCall.value.status = 'connected'
        beginConnectedDuration()
        if (disconnectTimer) clearTimeout(disconnectTimer)
        disconnectTimer = undefined
      } else if (peer.connectionState === 'failed') {
        failCall(new Error('The WebRTC connection failed. Check network and TURN configuration.'))
      } else if (peer.connectionState === 'disconnected' && !disconnectTimer) {
        activeCall.value.status = 'disconnected'
        disconnectTimer = setTimeout(() => {
          if (peer?.connectionState === 'disconnected') failCall(new Error('The call connection was lost.'))
        }, 10000)
      }
    }
  }

  function queueSignal (signal: CallSignal) {
    if (!claimCallSignalId(signal.id, handledSignalIds)) return
    let processed = false
    signalQueue = signalQueue.then(async () => {
      if (!activeCall.value || signal.call_id !== activeCall.value.id
          || !isSignalForCallParticipant(signal, activeCall.value, useAuthStore().userId)) return
      processed = await applySignal(signal)
    }).catch(reason => failCall(reason)).finally(() => {
      if (!processed || activeCall.value?.id !== signal.call_id) handledSignalIds.delete(signal.id)
    })
  }

  async function applySignal (signal: CallSignal) {
    const call = activeCall.value
    if (!peer || !call || !isSignalForCallParticipant(signal, call, useAuthStore().userId)
        || !await confirmCallStillActive(signal.call_id)) return false
    if (signal.signal_type === 'ice') {
      const candidate = signal.payload as RTCIceCandidateInit
      if (!candidate.candidate) return true
      if (!peer.remoteDescription) queuedIce.push(candidate)
      else await peer.addIceCandidate(new RTCIceCandidate(candidate))
      return true
    }

    const description = signal.payload as unknown as RTCSessionDescriptionInit
    if (!description.sdp || description.type !== signal.signal_type) throw new Error('Received invalid call signaling data.')
    await peer.setRemoteDescription(new RTCSessionDescription(description))
    await flushQueuedIce()
    if (signal.signal_type === 'offer') {
      const answer = await peer.createAnswer()
      await peer.setLocalDescription(answer)
      await sendSignal(signal.call_id, 'answer', { type: answer.type, sdp: answer.sdp })
    }
    return true
  }

  async function flushQueuedIce () {
    if (!peer?.remoteDescription) return
    const candidates = queuedIce
    queuedIce = []
    for (const candidate of candidates) await peer.addIceCandidate(new RTCIceCandidate(candidate))
  }

  async function sendSignal (callId: string, signalType: 'offer' | 'answer' | 'ice', payload: Record<string, unknown>) {
    if (!supabase) throw new Error('Secure call signaling is not configured.')
    const call = activeCall.value
    const userId = useAuthStore().userId
    const isExpectedSender = call?.id === callId && (signalType === 'offer'
      ? userId === call.caller_id && call.status === 'calling'
      : signalType === 'answer'
        ? userId === call.callee_id && call.status === 'connecting'
        : [call.caller_id, call.callee_id].includes(userId))
    if (!isExpectedSender) throw new Error('Call signaling is not valid for the current participant or call state.')
    const { error: rpcError } = await supabase.rpc('northstar_send_call_signal', {
      p_call_id: callId,
      p_signal_type: signalType,
      p_payload: payload,
    })
    if (rpcError) throw new Error(`Could not send private call signaling: ${rpcError.message}`)
  }

  async function changeCallStatus (callId: string, action: CallAction) {
    if (!supabase) return false
    const { data, error: rpcError } = await supabase.rpc('northstar_update_call_status', {
      p_call_id: callId,
      p_action: action,
    })
    if (rpcError) {
      error.value = `Could not ${action} the call. The server status could not be confirmed.`
      return false
    }
    const row = normalizeRow(data)
    const userId = useAuthStore().userId
    const knownCall = activeCall.value?.id === callId ? activeCall.value
      : incomingCall.value?.id === callId ? incomingCall.value : null
    if (!row || row.id !== callId || ![row.caller_id, row.callee_id].includes(userId)
        || (knownCall && (row.conversation_id !== knownCall.conversation_id
          || row.caller_id !== knownCall.caller_id || row.callee_id !== knownCall.callee_id
          || row.call_type !== knownCall.call_type))) {
      error.value = `The call server returned an invalid response for ${action}. Local call resources were released.`
      if (activeCall.value?.id === callId) releaseCallResources()
      if (incomingCall.value?.id === callId) {
        clearIncomingTimer()
        incomingCall.value = null
      }
      return false
    }
    if (row.status !== expectedStatusByAction[action]) {
      error.value = `The call server returned an unexpected state for ${action}. The local call state was resynchronized.`
      handleSessionChange(row)
      if (terminalStatuses.has(row.status)) {
        if (activeCall.value?.id === callId) releaseCallResources()
        if (incomingCall.value?.id === callId) {
          clearIncomingTimer()
          incomingCall.value = null
        }
      }
      return false
    }
    if (terminalStatuses.has(row.status)) {
      if (activeCall.value?.id === callId) releaseCallResources()
      if (incomingCall.value?.id === callId) {
        clearIncomingTimer()
        incomingCall.value = null
      }
    }
    return true
  }

  function setRingTimeout (callId: string, expiresAt: string) {
    clearRingTimer()
    ringTimer = setTimeout(async () => {
      if (activeCall.value?.id !== callId
          || (activeCall.value.status !== 'calling' && activeCall.value.status !== 'ringing')) return
      const markedMissed = await changeCallStatus(callId, 'missed')
      if (markedMissed) {
        if (activeCall.value?.id === callId) releaseCallResources()
        notice.value = 'The call was not answered.'
      } else if (activeCall.value?.id === callId
          && (activeCall.value.status === 'calling' || activeCall.value.status === 'ringing')) {
        rememberTerminalAction(activeCall.value, 'missed')
        releaseCallResources()
        error.value = 'The call invitation expired, but the server could not confirm its final status.'
      }
    }, invitationTimeRemaining(expiresAt))
  }

  function clearRingTimer () {
    if (ringTimer) clearTimeout(ringTimer)
    ringTimer = undefined
  }

  function startLeaseHeartbeat () {
    if (leaseTimer) clearInterval(leaseTimer)
    leaseTimer = setInterval(() => {
      if (!heartbeatInFlight && (activeCall.value?.status === 'connected' || activeCall.value?.status === 'connecting')) {
        heartbeatInFlight = true
        const callId = activeCall.value.id
        void changeCallStatus(callId, 'heartbeat').then(success => {
          if (!success && activeCall.value?.id === callId) {
            rememberTerminalAction(activeCall.value, 'failed')
            releaseCallResources()
          }
        }).finally(() => { heartbeatInFlight = false })
      }
    }, 15000)
  }

  function failCall (reason: unknown) {
    const row = activeCall.value
    if (row) void changeCallStatus(row.id, 'failed').then(success => {
      if (!success) rememberTerminalAction(row, 'failed')
    })
    error.value = reason instanceof Error ? reason.message : 'The call failed unexpectedly.'
    releaseCallResources()
  }

  function releaseMedia () {
    localStream.value?.getTracks().forEach(track => track.stop())
    remoteStream.value?.getTracks().forEach(track => track.stop())
    localStream.value = null
    remoteStream.value = null
    muted.value = false
    cameraEnabled.value = true
  }

  function releaseCallResources () {
    clearRingTimer()
    clearIncomingTimer()
    if (leaseTimer) clearInterval(leaseTimer)
    if (disconnectTimer) clearTimeout(disconnectTimer)
    if (durationTimer) clearInterval(durationTimer)
    leaseTimer = undefined
    disconnectTimer = undefined
    durationTimer = undefined
    screenStream?.getTracks().forEach(track => {
      track.onended = null
      track.stop()
    })
    screenStream = null
    screenVideoSender = null
    screenSharing.value = false
    connectedAt = null
    connectedDurationSeconds.value = 0
    if (peer) {
      peer.onicecandidate = null
      peer.ontrack = null
      peer.onconnectionstatechange = null
      peer.close()
    }
    peer = null
    queuedIce = []
    handledSignalIds.clear()
    heartbeatInFlight = false
    releaseMedia()
    activeCall.value = null
    minimized.value = false
  }

  function beginConnectedDuration () {
    if (connectedAt !== null) return
    connectedAt = Date.now()
    connectedDurationSeconds.value = 0
    durationTimer = setInterval(() => {
      if (connectedAt !== null) connectedDurationSeconds.value = Math.floor((Date.now() - connectedAt) / 1000)
    }, 1000)
  }

  function minimizeCall () {
    if (activeCall.value) minimized.value = true
  }

  function restoreCall () {
    minimized.value = false
  }

  async function stopListening (sendTerminalStatus = true) {
    startGeneration += 1
    listening = false
    clearReconnectTimers()
    if (terminalRetryTimer) clearTimeout(terminalRetryTimer)
    terminalRetryTimer = undefined
    unbindBrowserEvents()
    callStartInFlight.value = false
    if (sendTerminalStatus && activeCall.value) {
      const row = activeCall.value
      const action = row.status === 'calling' || row.status === 'ringing' ? 'cancel' : 'end'
      void changeCallStatus(row.id, action).then(success => {
        if (!success) rememberTerminalAction(row, action)
      })
    } else if (sendTerminalStatus && incomingCall.value) {
      const row = incomingCall.value
      void changeCallStatus(row.id, 'decline').then(success => {
        if (!success) rememberTerminalAction(row, 'decline')
      })
    }
    releaseCallResources()
    incomingCall.value = null
    const oldChannel = channel
    channel = null
    channelGeneration += 1
    if (oldChannel && supabase) {
      try {
        await supabase.removeChannel(oldChannel)
      } catch {
        error.value = 'Call signaling cleanup could not be confirmed. It will be recreated when the account reconnects.'
      }
    }
    channel = null
    signalingReady.value = false
    hasSubscribed = false
    subscriptionInterrupted = false
  }

  async function recoverCallState () {
    if (recoveryInFlight || !supabase) return
    recoveryInFlight = true
    try {
      if (!activeCall.value) {
        await loadPendingInvitation()
        await retryPendingTerminalActions()
        if (realtimeUnavailable) {
          realtimeUnavailable = false
          clearSubscriptionError()
        }
        return
      }
      const callId = activeCall.value.id
      const { data, error: sessionError } = await supabase.from('northstar_call_sessions')
        .select('id,conversation_id,caller_id,callee_id,call_type,status,expires_at')
        .eq('id', callId)
        .maybeSingle()
      if (sessionError) {
        error.value = `Could not restore call state after Realtime recovery: ${sessionError.message}`
        return
      }
      const row = normalizeRow(data)
      if (!row || row.id !== callId || ![row.caller_id, row.callee_id].includes(useAuthStore().userId)) {
        error.value = 'The active call is no longer available to this account.'
        releaseCallResources()
        return
      }
      const currentCall = activeCall.value
      if (!currentCall || row.conversation_id !== currentCall.conversation_id
          || row.caller_id !== currentCall.caller_id || row.callee_id !== currentCall.callee_id
          || row.call_type !== currentCall.call_type) {
        error.value = 'The server call details did not match the active call.'
        releaseCallResources()
        return
      }
      handleSessionChange(row)
      if (activeCall.value?.id !== callId) return
      if (!isCallSessionActive(row.status, row.expires_at)) {
        error.value = 'The call expired while Realtime was disconnected.'
        releaseCallResources()
        return
      }
      await recoverCallSignals(callId)
      await retryPendingTerminalActions()
      if (realtimeUnavailable) {
        realtimeUnavailable = false
        clearSubscriptionError()
      }
    } catch (reason) {
      error.value = reason instanceof Error ? `Could not restore the call after Realtime recovery: ${reason.message}`
        : 'Could not restore the call after Realtime recovery.'
    } finally {
      recoveryInFlight = false
    }
  }

  async function recoverCallSignals (callId: string) {
    if (!supabase || activeCall.value?.id !== callId) return
    const { data, error: signalError } = await supabase.from('northstar_call_signals')
      .select('id,call_id,sender_id,recipient_id,signal_type,payload')
      .eq('call_id', callId)
      .order('created_at', { ascending: true })
      .order('id', { ascending: true })
    if (signalError) {
      error.value = `Could not recover call signaling: ${signalError.message}`
      return
    }
    if (activeCall.value?.id !== callId || !await confirmCallStillActive(callId)) return
    for (const signal of (data ?? []) as CallSignal[]) {
      if (signal.call_id === callId && signal.recipient_id === useAuthStore().userId) queueSignal(signal)
    }
  }

  async function confirmCallStillActive (callId: string, requiredStatus?: 'accepted') {
    if (!supabase || activeCall.value?.id !== callId) return false
    const { data, error: queryError } = await supabase.from('northstar_call_sessions')
      .select('id,conversation_id,caller_id,callee_id,call_type,status,expires_at')
      .eq('id', callId)
      .maybeSingle()
    if (queryError) {
      error.value = `Could not verify call state before processing signaling: ${queryError.message}`
      return false
    }
    const row = normalizeRow(data)
    if (!row || row.id !== callId || ![row.caller_id, row.callee_id].includes(useAuthStore().userId)) {
      error.value = 'The call is no longer available to this account.'
      releaseCallResources()
      return false
    }
    const currentCall = activeCall.value
    if (!currentCall || row.conversation_id !== currentCall.conversation_id
        || row.caller_id !== currentCall.caller_id || row.callee_id !== currentCall.callee_id
        || row.call_type !== currentCall.call_type) {
      error.value = 'The server call details did not match the active call.'
      releaseCallResources()
      return false
    }
    if (terminalStatuses.has(row.status)) {
      handleSessionChange(row)
      return false
    }
    if (!isCallSessionActive(row.status, row.expires_at)
        || (requiredStatus && row.status !== requiredStatus)) {
      error.value = 'The call expired or changed state before signaling recovery completed.'
      releaseCallResources()
      return false
    }
    return true
  }

  function rememberTerminalAction (call: CallRow, action: Exclude<CallAction, 'heartbeat'>) {
    const previous = pendingTerminalActions.get(call.id)
    pendingTerminalActions.set(call.id, {
      action,
      call,
      attempts: previous?.action === action ? previous.attempts : 0,
    })
    scheduleTerminalRetry()
  }

  function scheduleTerminalRetry () {
    if (!listening || !signalingReady.value || terminalRetryTimer || !pendingTerminalActions.size) return
    const delays = [1_000, 3_000, 10_000]
    const retryable = [...pendingTerminalActions.values()].filter(item => item.attempts < delays.length)
    if (!retryable.length) return
    const attempt = Math.min(...retryable.map(item => item.attempts))
    terminalRetryTimer = setTimeout(() => {
      terminalRetryTimer = undefined
      void retryPendingTerminalActions()
    }, delays[attempt])
  }

  async function retryPendingTerminalActions () {
    if (!supabase || !signalingReady.value) return
    for (const [callId, pending] of pendingTerminalActions) {
      if (terminalRetryInFlight.has(callId) || pending.attempts >= 3) continue
      terminalRetryInFlight.add(callId)
      try {
        const { data, error: queryError } = await supabase.from('northstar_call_sessions')
          .select('id,conversation_id,caller_id,callee_id,call_type,status,expires_at')
          .eq('id', callId)
          .maybeSingle()
        if (queryError) {
          pending.attempts += 1
          continue
        }
        const row = normalizeRow(data)
        if (!row || row.id !== callId || row.caller_id !== pending.call.caller_id
            || row.callee_id !== pending.call.callee_id || ![row.caller_id, row.callee_id].includes(useAuthStore().userId)) {
          pendingTerminalActions.delete(callId)
          continue
        }
        if (terminalStatuses.has(row.status)) {
          pendingTerminalActions.delete(callId)
          continue
        }
        const currentUser = useAuthStore().userId
        const actionStillValid = pending.action === 'cancel'
          ? row.status === 'ringing' && currentUser === row.caller_id
          : pending.action === 'decline'
            ? row.status === 'ringing' && currentUser === row.callee_id
            : pending.action === 'missed'
              ? row.status === 'ringing' && currentUser === row.caller_id
              : pending.action === 'end'
                ? row.status === 'accepted'
                : row.status === 'ringing' || row.status === 'accepted'
        if (!actionStillValid) continue
        // The persisted row is checked first, so we never blindly replay a terminal
        // mutation after an ambiguous network failure.
        if (await changeCallStatus(callId, pending.action)) pendingTerminalActions.delete(callId)
        else pending.attempts += 1
      } catch {
        pending.attempts += 1
        error.value = 'A call status update is still awaiting confirmation. It will be checked after signaling reconnects.'
      } finally {
        terminalRetryInFlight.delete(callId)
      }
    }
    scheduleTerminalRetry()
  }

  async function getRtcConfiguration (): Promise<RTCConfiguration> {
    const stunUrls = (import.meta.env.VITE_NORTHSTAR_STUN_URLS ?? '').split(',').map((url: string) => url.trim()).filter(Boolean)
    const configuredApiBase = import.meta.env.VITE_NORTHSTAR_API_BASE_URL?.trim()
    let endpoint = '/api/v1/calls/ice-servers'
    if (configuredApiBase) {
      let apiBase: URL
      try {
        apiBase = new URL(configuredApiBase)
      } catch {
        throw new Error('The Northstar API URL is invalid.')
      }
      const localHttpHost = ['localhost', '127.0.0.1', '[::1]'].includes(apiBase.hostname)
      if ((apiBase.protocol !== 'https:' && !(apiBase.protocol === 'http:' && localHttpHost))
          || apiBase.username || apiBase.password || apiBase.pathname !== '/' || apiBase.search || apiBase.hash) {
        throw new Error('The Northstar API URL must be a secure API origin.')
      }
      endpoint = new URL('/api/v1/calls/ice-servers', apiBase).toString()
    }

    const { data, error: sessionError } = await supabase!.auth.getSession()
    if (sessionError || !data.session?.access_token) throw new Error('Sign in again to obtain temporary call credentials.')

    let response: Response
    try {
      response = await fetch(endpoint, {
        headers: { Authorization: `Bearer ${data.session.access_token}` },
        cache: 'no-store',
        credentials: 'omit',
      })
    } catch {
      throw new Error('Temporary call credentials could not be loaded.')
    }
    if (!response.ok) throw new Error(`Temporary call credentials could not be loaded (${response.status}).`)

    let result: { ice_servers?: unknown, expires_at?: unknown }
    try {
      result = await response.json() as { ice_servers?: unknown, expires_at?: unknown }
    } catch {
      throw new Error('The call credential service returned an invalid response.')
    }
    if (!Array.isArray(result.ice_servers) || result.ice_servers.length === 0
        || result.ice_servers.length > 32 || typeof result.expires_at !== 'string'
        || !Number.isFinite(Date.parse(result.expires_at)) || Date.parse(result.expires_at) <= Date.now() + 15000) {
      throw new Error('The call credential service returned invalid or expiring credentials.')
    }

    const servers: RTCIceServer[] = []
    for (const item of result.ice_servers) {
      if (!item || typeof item !== 'object') throw new Error('The call credential service returned invalid ICE servers.')
      const server = item as { urls?: unknown, username?: unknown, credential?: unknown }
      const urls = typeof server.urls === 'string'
        ? [server.urls]
        : Array.isArray(server.urls) ? server.urls : []
      if (!urls.length || urls.some(url => typeof url !== 'string' || !/^(stun|stuns|turn|turns):/i.test(url))) {
        throw new Error('The call credential service returned invalid ICE server URLs.')
      }
      const hasTurn = urls.some(url => /^(turn|turns):/i.test(url as string))
      if (hasTurn && (typeof server.username !== 'string' || !server.username
          || typeof server.credential !== 'string' || !server.credential)) {
        throw new Error('The call credential service returned incomplete TURN credentials.')
      }
      servers.push({
        urls: server.urls as string | string[],
        ...(hasTurn ? { username: server.username as string, credential: server.credential as string } : {}),
      })
    }
    if (!servers.some(server => (Array.isArray(server.urls) ? server.urls : [server.urls]).some(url => /^(turn|turns):/i.test(url)))) {
      throw new Error('The call credential service did not return a TURN server.')
    }
    if (stunUrls.length) servers.unshift({ urls: stunUrls })
    return { iceServers: servers, iceCandidatePoolSize: 4 }
  }

  return {
    activeCall, incomingCall, localStream, remoteStream, muted, cameraEnabled, screenSharing, callStartInFlight, incomingActionInFlight,
    signalingReady, minimized, connectedDurationSeconds,
    error, notice, isInCall, startListening, stopListening, startCall,
    acceptIncomingCall, declineIncomingCall, endCall, toggleMute, toggleCamera, toggleScreenSharing,
    minimizeCall, restoreCall,
  }
})

function normalizeRow (data: unknown): CallRow | null {
  const row = Array.isArray(data) ? data[0] : data
  if (!row || typeof row !== 'object') return null
  const value = row as Partial<CallRow>
  if (!isUuid(value.id) || !isUuid(value.conversation_id)
      || !isUuid(value.caller_id) || !isUuid(value.callee_id) || value.caller_id === value.callee_id
      || (value.call_type !== 'audio' && value.call_type !== 'video')
      || typeof value.status !== 'string' || !knownServerStatuses.has(value.status)
      || typeof value.expires_at !== 'string' || !Number.isFinite(Date.parse(value.expires_at))) return null
  return value as CallRow
}
