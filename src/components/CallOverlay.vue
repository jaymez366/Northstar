<script setup lang="ts">
  import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
  import { useRouter } from 'vue-router'
  import { useCallsStore } from '@/stores/calls'
  import { useAuthStore } from '@/stores/auth'
  import { useWorkspaceStore } from '@/stores/workspace'

  const calls = useCallsStore()
  const auth = useAuthStore()
  const workspace = useWorkspaceStore()
  const router = useRouter()
  const localVideo = ref<HTMLVideoElement | null>(null)
  const miniVideo = ref<HTMLVideoElement | null>(null)
  const remoteVideo = ref<HTMLVideoElement | null>(null)
  const remoteAudio = ref<HTMLAudioElement | null>(null)
  const outputDevices = ref<MediaDeviceInfo[]>([])
  const selectedOutput = ref('')
  const outputSelectionSupported = ref(false)
  const otherParticipantId = computed(() => {
    const call = calls.activeCall ?? calls.incomingCall
    if (!call) return null
    return call.caller_id === auth.userId ? call.callee_id : call.caller_id
  })
  const participantName = computed(() => {
    const employee = workspace.employees.find(item => item.id === otherParticipantId.value)
    return employee ? `${employee.firstName} ${employee.lastName}`.trim() : 'Colleague'
  })
  const callStateLabel = computed(() => {
    if (calls.activeCall?.status === 'starting') return 'Preparing call…'
    if (calls.activeCall?.status === 'ringing') return 'Ringing…'
    if (calls.activeCall?.status === 'connecting') return 'Connecting…'
    if (calls.activeCall?.status === 'disconnected') return 'Connection lost · trying to reconnect…'
    if (calls.activeCall?.status === 'connected') return 'Connected'
    return ''
  })
  const formattedDuration = computed(() => {
    const seconds = calls.connectedDurationSeconds
    return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`
  })

  async function refreshAudioOutputs () {
    if (!navigator.mediaDevices?.enumerateDevices) return
    try {
      outputDevices.value = (await navigator.mediaDevices.enumerateDevices()).filter(device => device.kind === 'audiooutput')
      const sinkElement = remoteAudio.value ?? remoteVideo.value
      outputSelectionSupported.value = Boolean(sinkElement && 'setSinkId' in sinkElement && outputDevices.value.length > 0)
      if (sinkElement && 'getSinkId' in sinkElement) {
        selectedOutput.value = await (sinkElement as HTMLMediaElement & { getSinkId: () => Promise<string> }).getSinkId()
      }
    } catch {
      outputDevices.value = []
      outputSelectionSupported.value = false
    }
  }

  async function changeAudioOutput (event: Event) {
    const sinkId = (event.target as HTMLSelectElement).value
    const element = remoteAudio.value ?? remoteVideo.value
    if (!element || !('setSinkId' in element)) {
      outputSelectionSupported.value = false
      return
    }
    try {
      await (element as HTMLMediaElement & { setSinkId: (id: string) => Promise<void> }).setSinkId(sinkId)
      selectedOutput.value = sinkId
    } catch {
      calls.error = 'The browser could not switch audio output. Check the selected device and browser permissions.'
    }
  }

  function openCallChat () {
    const call = calls.activeCall ?? calls.incomingCall
    if (call) void router.push({ path: '/messages', query: { conversation: call.conversation_id } })
  }

  const mediaDeviceChangeHandler = () => { void refreshAudioOutputs() }

  watch(() => [calls.localStream, calls.remoteStream, calls.activeCall?.call_type, calls.minimized], async () => {
    await nextTick()
    if (localVideo.value && calls.localStream) localVideo.value.srcObject = calls.localStream
    if (miniVideo.value && calls.localStream) miniVideo.value.srcObject = calls.localStream
    if (remoteVideo.value && calls.remoteStream) remoteVideo.value.srcObject = calls.remoteStream
    if (remoteAudio.value && calls.remoteStream) remoteAudio.value.srcObject = calls.remoteStream
    if (calls.activeCall) void refreshAudioOutputs()
  }, { immediate: true })

  onMounted(() => {
    calls.startListening()
    navigator.mediaDevices?.addEventListener?.('devicechange', mediaDeviceChangeHandler)
  })
  onUnmounted(() => {
    navigator.mediaDevices?.removeEventListener?.('devicechange', mediaDeviceChangeHandler)
    void calls.stopListening()
  })
</script>

<template>
  <section
    v-if="calls.incomingCall || calls.activeCall || calls.error || calls.notice"
    class="call-overlay"
    :class="{ 'is-minimized': calls.minimized && calls.activeCall }"
    :role="calls.minimized && calls.activeCall ? 'region' : 'dialog'"
    :aria-modal="calls.minimized ? undefined : 'true'"
    :aria-label="calls.minimized ? 'Minimized Northstar call' : 'Northstar call'"
  >
    <article v-if="calls.minimized && calls.activeCall" class="mini-call" aria-live="polite">
      <video
        v-if="calls.activeCall.call_type === 'video' && calls.localStream"
        ref="miniVideo"
        class="mini-video"
        autoplay
        muted
        playsinline
        aria-label="Your camera preview"
      />
      <div class="mini-copy">
        <strong>{{ participantName }}</strong>
        <span>{{ callStateLabel }}<template v-if="calls.activeCall.status === 'connected'"> · {{ formattedDuration }}</template></span>
      </div>
      <div class="mini-actions">
        <button type="button" :aria-pressed="calls.muted" :aria-label="calls.muted ? 'Unmute microphone' : 'Mute microphone'" @click="calls.toggleMute">
          <v-icon :icon="calls.muted ? 'mdi-microphone-off' : 'mdi-microphone'" size="18" />
        </button>
        <button type="button" aria-label="Restore call window" title="Restore call" @click="calls.restoreCall">
          <v-icon icon="mdi-arrow-expand" size="18" />
        </button>
        <button class="end-mini" type="button" aria-label="End call" @click="calls.endCall">
          <v-icon icon="mdi-phone-hangup" size="18" />
        </button>
      </div>
    </article>

    <div v-else class="call-card">
      <header>
        <span class="call-mark"><v-icon icon="mdi-phone-in-talk" size="19" /></span>
        <strong>{{ calls.activeCall?.call_type === 'video' || calls.incomingCall?.call_type === 'video' ? 'Video call' : 'Voice call' }}</strong>
        <button v-if="calls.activeCall" class="minimize-button" type="button" aria-label="Minimize call" title="Minimize call" @click="calls.minimizeCall">
          <v-icon icon="mdi-arrow-collapse" size="20" /> Minimize
        </button>
        <button v-if="calls.activeCall" class="call-header-action" type="button" disabled aria-label="Add participant unavailable" title="This call backend currently supports one-to-one calls only"><v-icon icon="mdi-account-plus-outline" size="19" /></button>
      </header>
      <p v-if="calls.incomingCall && !calls.activeCall" class="call-message">Incoming {{ calls.incomingCall.call_type }} call from {{ participantName }}</p>
      <p v-else-if="calls.activeCall" class="call-message">
        {{ participantName }} <span>{{ callStateLabel }}<template v-if="calls.activeCall.status === 'connected'"> · {{ formattedDuration }}</template></span>
      </p>
      <div v-if="calls.activeCall?.call_type === 'video' && calls.localStream" class="video-stage">
        <video v-if="calls.remoteStream" ref="remoteVideo" class="call-video remote" autoplay playsinline aria-label="Remote participant video" />
        <video ref="localVideo" class="call-video local" autoplay muted playsinline aria-label="Your camera preview" />
      </div>
      <audio v-if="calls.activeCall?.call_type === 'audio' && calls.remoteStream" ref="remoteAudio" autoplay />
      <p v-if="calls.error" class="call-error" role="alert">{{ calls.error }}</p>
      <p v-else-if="calls.notice" class="call-notice" role="status">{{ calls.notice }}</p>
      <p v-if="calls.screenSharing" class="call-notice" role="status">Your selected screen or window is being shared. Use the screen button to stop sharing.</p>
      <p v-if="!calls.signalingReady && (calls.activeCall || calls.incomingCall)" class="call-notice" role="status">Signaling is reconnecting. The media connection will remain open while it recovers.</p>
      <div v-if="calls.incomingCall && !calls.activeCall" class="call-actions">
        <button class="decline" type="button" :disabled="calls.incomingActionInFlight" @click="calls.declineIncomingCall"><v-icon icon="mdi-phone-hangup" size="18" /> Decline</button>
        <button class="accept" type="button" :disabled="!calls.signalingReady || calls.incomingActionInFlight" @click="calls.acceptIncomingCall"><v-icon icon="mdi-phone" size="18" /> {{ calls.incomingActionInFlight ? 'Accepting…' : 'Accept' }}</button>
      </div>
      <div v-if="calls.activeCall" class="call-bottom-bar" aria-label="Call options">
        <label class="audio-output-control" :title="outputSelectionSupported ? 'Choose audio output' : 'Audio output selection is unavailable in this browser or device'">
          <v-icon icon="mdi-volume-high" size="18" />
          <select aria-label="Audio output device" :disabled="!outputSelectionSupported" :value="selectedOutput" @change="changeAudioOutput">
            <option v-if="!outputSelectionSupported" value="">Output unavailable</option>
            <option v-for="(device, index) in outputDevices" :key="device.deviceId || index" :value="device.deviceId">{{ device.label || `Audio output ${index + 1}` }}</option>
          </select>
        </label>
        <button type="button" :disabled="calls.activeCall.status === 'starting'" :aria-pressed="calls.muted" :aria-label="calls.muted ? 'Unmute microphone' : 'Mute microphone'" :title="calls.muted ? 'Unmute microphone' : 'Mute microphone'" @click="calls.toggleMute"><v-icon :icon="calls.muted ? 'mdi-microphone-off' : 'mdi-microphone'" size="19" /></button>
        <button v-if="calls.activeCall.call_type === 'video'" type="button" :disabled="calls.activeCall.status === 'starting'" :aria-pressed="!calls.cameraEnabled" :aria-label="calls.cameraEnabled ? 'Turn camera off' : 'Turn camera on'" :title="calls.cameraEnabled ? 'Turn camera off' : 'Turn camera on'" @click="calls.toggleCamera"><v-icon :icon="calls.cameraEnabled ? 'mdi-video' : 'mdi-video-off'" size="19" /></button>
        <button type="button" disabled title="Live voice/video mode switching requires additional call renegotiation support" aria-label="Switch voice or video mode unavailable"><v-icon icon="mdi-video-switch-outline" size="19" /></button>
        <button type="button" class="more-control" @click="openCallChat" aria-label="Open this conversation"><v-icon icon="mdi-message-outline" size="19" /><span>Message</span></button>
        <button type="button" :disabled="calls.activeCall.call_type !== 'video' || calls.activeCall.status !== 'connected' || !calls.cameraEnabled" :title="calls.screenSharing ? 'Stop screen sharing' : calls.activeCall.call_type !== 'video' ? 'Switch to a video call before sharing your screen' : !calls.cameraEnabled ? 'Turn your camera on before sharing your screen' : 'Share your screen'" :aria-label="calls.screenSharing ? 'Stop screen sharing' : 'Share your screen'" :aria-pressed="calls.screenSharing" @click="calls.toggleScreenSharing"><v-icon :icon="calls.screenSharing ? 'mdi-monitor-off' : 'mdi-monitor-share'" size="19" /></button>
        <button type="button" class="end-call-control" :disabled="calls.activeCall.status === 'starting'" aria-label="End call" title="End call" @click="calls.endCall"><v-icon icon="mdi-phone-hangup" size="19" /></button>
      </div>
      <button v-if="!calls.activeCall && !calls.incomingCall" type="button" class="dismiss" @click="calls.error = ''; calls.notice = ''">Dismiss</button>
    </div>
  </section>
</template>

<style scoped>
.call-overlay { position: fixed; z-index: 10000; inset: 0; display: grid; place-items: center; padding: 20px; background: rgb(15 25 20 / 58%); }
.call-overlay.is-minimized { inset: auto 18px 18px auto; display: block; width: min(420px, calc(100vw - 24px)); padding: 0; background: transparent; }
.call-card { position: relative; display: grid; width: min(100%, 460px); gap: 16px; border: 1px solid var(--ns-border, #dce4d8); border-radius: 18px; padding: 22px; background: var(--ns-surface, #fff); box-shadow: 0 24px 70px rgb(0 0 0 / 26%); color: var(--ns-text-primary, #18352d); }
.call-card header { display: flex; align-items: center; gap: 10px; }
.call-header-action { display: grid; width: 38px; height: 38px; place-items: center; margin-left: 2px; border: 1px solid var(--ns-border, #dce4d8); border-radius: 50%; background: var(--ns-surface, #fff); color: var(--ns-text-secondary, #64756b); }
.call-header-action:disabled { cursor: not-allowed; opacity: .48; }
.call-mark { display: grid; width: 38px; height: 38px; place-items: center; border-radius: 50%; background: var(--ns-bg-f5f7f1, #f5f7f1); }
.minimize-button { display: inline-flex; min-height: 38px; align-items: center; gap: 4px; margin-left: auto; border: 1px solid var(--ns-border, #dce4d8); border-radius: 999px; padding: 0 10px; background: var(--ns-surface, #fff); color: inherit; cursor: pointer; }
.call-message { margin: 0; color: var(--ns-text-secondary, #64756b); font-size: 14px; }
.call-message span { margin-left: 5px; font-size: 12px; }
.video-stage { position: relative; min-height: 180px; }
.call-video { width: 100%; max-height: 320px; border-radius: 12px; background: #111; object-fit: cover; }
.call-video.remote { min-height: 180px; }
.call-video.local { position: absolute; right: 10px; bottom: 10px; width: 110px; max-height: 100px; border: 2px solid white; }
.call-error, .call-notice { margin: 0; border-radius: 8px; padding: 10px; background: #fff2ef; color: #9b3328; font-size: 12px; }
.call-notice { background: var(--ns-bg-f5f7f1, #f5f7f1); color: var(--ns-text-secondary, #64756b); }
.call-actions { display: flex; flex-wrap: wrap; justify-content: center; gap: 12px; }
.call-actions button, .dismiss { display: inline-flex; min-width: 48px; min-height: 44px; align-items: center; justify-content: center; gap: 7px; border: 1px solid var(--ns-border, #dce4d8); border-radius: 999px; padding: 0 16px; background: var(--ns-surface, #fff); color: inherit; cursor: pointer; }
.call-actions button:disabled { cursor: wait; opacity: .6; }
.call-actions .accept { border-color: #15803d; background: #15803d; color: white; }
.call-actions .decline { border-color: #b42318; background: #b42318; color: white; }
.call-bottom-bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-around; gap: 8px; border: 1px solid var(--ns-border, #dce4d8); border-radius: 24px; padding: 9px 12px; background: var(--ns-bg-f5f7f1, #f5f7f1); }
.call-bottom-bar > button { display: grid; width: 42px; height: 42px; flex: 0 0 auto; place-items: center; border: 1px solid var(--ns-border, #dce4d8); border-radius: 50%; background: var(--ns-surface, #fff); color: var(--ns-text-primary, #18352d); cursor: pointer; }
.call-bottom-bar > button:disabled { cursor: not-allowed; opacity: .45; }
.call-bottom-bar > .end-call-control { border-color: #b42318; background: #b42318; color: #fff; }
.call-bottom-bar > .more-control { display: flex; width: auto; gap: 6px; border-radius: 999px; padding: 0 12px; font-size: 11px; }
.audio-output-control { display: flex; min-width: 0; flex: 1 0 100%; align-items: center; justify-content: center; gap: 5px; color: var(--ns-text-primary, #18352d); }
.audio-output-control select { width: min(126px, 24vw); min-width: 0; border: 0; background: transparent; color: inherit; font: inherit; font-size: 10px; }
.audio-output-control select:disabled { cursor: not-allowed; opacity: .65; }
.dismiss { justify-self: end; }
.mini-call { display: flex; min-height: 78px; align-items: center; gap: 12px; border: 1px solid var(--ns-border, #dce4d8); border-radius: 16px; padding: 10px; background: var(--ns-surface, #fff); box-shadow: 0 12px 40px rgb(0 0 0 / 24%); color: var(--ns-text-primary, #18352d); }
.mini-video { width: 72px; height: 56px; flex: 0 0 auto; border-radius: 9px; background: #111; object-fit: cover; }
.mini-copy { display: grid; min-width: 0; flex: 1; gap: 5px; }
.mini-copy strong, .mini-copy span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.mini-copy strong { font-size: 13px; }
.mini-copy span { color: var(--ns-text-secondary, #64756b); font-size: 11px; }
.mini-actions { display: flex; flex: 0 0 auto; gap: 5px; }
.mini-actions button { display: grid; width: 36px; height: 36px; place-items: center; border: 1px solid var(--ns-border, #dce4d8); border-radius: 50%; background: var(--ns-surface, #fff); color: inherit; cursor: pointer; }
.mini-actions .end-mini { border-color: #b42318; background: #b42318; color: #fff; }
@media (max-width: 520px) {
  .call-overlay.is-minimized { inset: auto 8px 8px; width: auto; }
  .mini-call { gap: 7px; padding: 8px; }
  .mini-video { width: 54px; height: 48px; }
  .mini-actions { gap: 3px; }
  .mini-actions button { width: 34px; height: 34px; }
  .call-bottom-bar { gap: 5px; padding: 7px; }
  .call-bottom-bar > button { width: 36px; height: 36px; }
  .audio-output-control select { width: 92px; }
}
</style>
