<script setup lang="ts">
  import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
  import { useCallsStore } from '@/stores/calls'
  import { useWorkspaceStore } from '@/stores/workspace'

  const calls = useCallsStore()
  const workspace = useWorkspaceStore()
  const localVideo = ref<HTMLVideoElement | null>(null)
  const remoteVideo = ref<HTMLVideoElement | null>(null)
  const remoteAudio = ref<HTMLAudioElement | null>(null)
  const callerName = computed(() => {
    const callerId = calls.incomingCall?.caller_id ?? calls.activeCall?.callee_id
    const employee = workspace.employees.find(item => item.id === callerId)
    return employee ? `${employee.firstName} ${employee.lastName}`.trim() : 'Colleague'
  })
  const callStateLabel = computed(() => {
    if (calls.activeCall?.status === 'starting') return 'Preparing secure call…'
    if (calls.activeCall?.status === 'ringing') return 'Ringing…'
    if (calls.activeCall?.status === 'connecting') return 'Connecting…'
    if (calls.activeCall?.status === 'connected') return 'Connected'
    return ''
  })

  watch(() => [calls.localStream, calls.remoteStream, calls.activeCall?.call_type], async () => {
    await nextTick()
    if (localVideo.value && calls.localStream) localVideo.value.srcObject = calls.localStream
    if (remoteVideo.value && calls.remoteStream) remoteVideo.value.srcObject = calls.remoteStream
    if (remoteAudio.value && calls.remoteStream) remoteAudio.value.srcObject = calls.remoteStream
  }, { immediate: true })

  onMounted(calls.startListening)
  onUnmounted(() => { void calls.stopListening() })
</script>

<template>
  <section v-if="calls.incomingCall || calls.activeCall || calls.error || calls.notice" class="call-overlay" role="dialog" aria-modal="true" aria-label="Northstar call">
    <div class="call-card">
      <header><span class="call-mark"><v-icon icon="mdi-phone-in-talk" size="19" /></span><strong>{{ calls.activeCall?.call_type === 'video' || calls.incomingCall?.call_type === 'video' ? 'Video call' : 'Voice call' }}</strong></header>
      <p v-if="calls.incomingCall && !calls.activeCall" class="call-message">Incoming {{ calls.incomingCall.call_type }} call from {{ callerName }}</p>
      <p v-else-if="calls.activeCall" class="call-message">{{ callerName }} <span>{{ callStateLabel }}</span></p>
      <video v-if="calls.activeCall?.call_type === 'video' && calls.remoteStream" ref="remoteVideo" class="call-video remote" autoplay playsinline aria-label="Remote participant video" />
      <video v-if="calls.activeCall?.call_type === 'video' && calls.localStream" ref="localVideo" class="call-video local" autoplay muted playsinline aria-label="Your camera preview" />
      <audio v-if="calls.activeCall?.call_type === 'audio' && calls.remoteStream" ref="remoteAudio" autoplay />
      <p v-if="calls.error" class="call-error" role="alert">{{ calls.error }}</p>
      <p v-else-if="calls.notice" class="call-notice" role="status">{{ calls.notice }}</p>
      <div v-if="calls.incomingCall && !calls.activeCall" class="call-actions">
        <button class="decline" type="button" @click="calls.declineIncomingCall"><v-icon icon="mdi-phone-hangup" size="18" /> Decline</button>
        <button class="accept" type="button" @click="calls.acceptIncomingCall"><v-icon icon="mdi-phone" size="18" /> Accept</button>
      </div>
      <div v-else-if="calls.activeCall" class="call-actions">
        <button type="button" :disabled="calls.activeCall.status === 'starting'" :aria-pressed="calls.muted" :aria-label="calls.muted ? 'Unmute microphone' : 'Mute microphone'" @click="calls.toggleMute"><v-icon :icon="calls.muted ? 'mdi-microphone-off' : 'mdi-microphone'" size="19" /></button>
        <button v-if="calls.activeCall.call_type === 'video'" type="button" :disabled="calls.activeCall.status === 'starting'" :aria-pressed="!calls.cameraEnabled" :aria-label="calls.cameraEnabled ? 'Turn camera off' : 'Turn camera on'" @click="calls.toggleCamera"><v-icon :icon="calls.cameraEnabled ? 'mdi-video' : 'mdi-video-off'" size="19" /></button>
        <button class="decline" type="button" :disabled="calls.activeCall.status === 'starting'" aria-label="End call" @click="calls.endCall"><v-icon icon="mdi-phone-hangup" size="19" /> End</button>
      </div>
      <button v-else type="button" class="dismiss" @click="calls.error = ''; calls.notice = ''">Dismiss</button>
    </div>
  </section>
</template>

<style scoped>
.call-overlay { position: fixed; z-index: 10000; inset: 0; display: grid; place-items: center; padding: 20px; background: rgb(15 25 20 / 58%); }
.call-card { position: relative; display: grid; width: min(100%, 420px); gap: 16px; border: 1px solid var(--ns-border, #dce4d8); border-radius: 18px; padding: 22px; background: var(--ns-surface, #fff); box-shadow: 0 24px 70px rgb(0 0 0 / 26%); color: var(--ns-text-primary, #18352d); }
.call-card header { display: flex; align-items: center; gap: 10px; }
.call-mark { display: grid; width: 38px; height: 38px; place-items: center; border-radius: 50%; background: var(--ns-bg-f5f7f1, #f5f7f1); }
.call-message { margin: 0; color: var(--ns-text-secondary, #64756b); font-size: 14px; }
.call-message span { margin-left: 5px; font-size: 12px; }
.call-video { width: 100%; max-height: 320px; border-radius: 12px; background: #111; object-fit: cover; }
.call-video.local { position: absolute; right: 34px; bottom: 105px; width: 100px; max-height: 100px; border: 2px solid white; }
.call-error, .call-notice { margin: 0; border-radius: 8px; padding: 10px; background: #fff2ef; color: #9b3328; font-size: 12px; }
.call-notice { background: var(--ns-bg-f5f7f1, #f5f7f1); color: var(--ns-text-secondary, #64756b); }
.call-actions { display: flex; justify-content: center; gap: 12px; }
.call-actions button, .dismiss { display: inline-flex; min-width: 48px; min-height: 44px; align-items: center; justify-content: center; gap: 7px; border: 1px solid var(--ns-border, #dce4d8); border-radius: 999px; padding: 0 16px; background: var(--ns-surface, #fff); color: inherit; cursor: pointer; }
.call-actions button:disabled { cursor: wait; opacity: .6; }
.call-actions .accept { border-color: #15803d; background: #15803d; color: white; }
.call-actions .decline { border-color: #b42318; background: #b42318; color: white; }
.dismiss { justify-self: end; }
</style>
