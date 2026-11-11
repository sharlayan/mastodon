import { defineMessages } from 'react-intl';

export const voiceMessages = defineMessages({
  join: { id: 'chat.voice.join', defaultMessage: 'Join call' },
  startCall: { id: 'chat.voice.start', defaultMessage: 'Start a call' },
  leave: { id: 'chat.voice.leave', defaultMessage: 'Leave call' },
  muteMic: { id: 'chat.voice.mute_mic', defaultMessage: 'Mute microphone' },
  unmuteMic: {
    id: 'chat.voice.unmute_mic',
    defaultMessage: 'Unmute microphone',
  },
  deafen: { id: 'chat.voice.deafen', defaultMessage: 'Turn off sound' },
  undeafen: { id: 'chat.voice.undeafen', defaultMessage: 'Turn on sound' },
  shareScreen: {
    id: 'chat.voice.share_screen',
    defaultMessage: 'Share screen',
  },
  stopSharing: {
    id: 'chat.voice.stop_sharing',
    defaultMessage: 'Stop sharing',
  },
  settings: { id: 'chat.voice.settings', defaultMessage: 'Call settings' },
  inCall: {
    id: 'chat.voice.in_call',
    defaultMessage: '{count, plural, one {# person} other {# people}} in call',
  },
  connecting: { id: 'chat.voice.connecting', defaultMessage: 'Connecting…' },
  reconnecting: {
    id: 'chat.voice.reconnecting',
    defaultMessage: 'Reconnecting…',
  },
  connected: { id: 'chat.voice.connected', defaultMessage: 'In call' },
  backToRoom: { id: 'chat.voice.back_to_room', defaultMessage: 'Open chat' },
  enableAudio: {
    id: 'chat.voice.enable_audio',
    defaultMessage: 'Click to play call audio',
  },
  watch: { id: 'chat.voice.watch', defaultMessage: 'Watch screen' },
  stopWatching: {
    id: 'chat.voice.stop_watching',
    defaultMessage: 'Stop watching',
  },
  fullscreen: { id: 'chat.voice.fullscreen', defaultMessage: 'Full screen' },
  pictureInPicture: {
    id: 'chat.voice.picture_in_picture',
    defaultMessage: 'Picture in picture',
  },
  participantMenu: {
    id: 'chat.voice.participant_menu',
    defaultMessage: 'Options for {name}',
  },
  voiceVolume: {
    id: 'chat.voice.voice_volume',
    defaultMessage: 'Voice volume',
  },
  screenVolume: {
    id: 'chat.voice.screen_volume',
    defaultMessage: 'Screen share volume',
  },
  forceMute: {
    id: 'chat.voice.force_mute',
    defaultMessage: 'Mute for everyone',
  },
  removeFromCall: {
    id: 'chat.voice.remove_from_call',
    defaultMessage: 'Remove from call',
  },
  removeConfirmTitle: {
    id: 'chat.voice.remove_confirm.title',
    defaultMessage: 'Remove {name} from the call?',
  },
  removeConfirmMessage: {
    id: 'chat.voice.remove_confirm.message',
    defaultMessage: 'They can’t rejoin this call for 10 minutes.',
  },
  you: { id: 'chat.voice.you', defaultMessage: 'You' },
  micMuted: { id: 'chat.voice.mic_muted', defaultMessage: 'Microphone muted' },
  deafened: { id: 'chat.voice.deafened', defaultMessage: 'Sound turned off' },
  sharingScreen: {
    id: 'chat.voice.sharing_screen',
    defaultMessage: 'Sharing screen',
  },
  callUnavailableNow: {
    id: 'chat.voice.unavailable_now',
    defaultMessage: 'The call status cannot be checked right now.',
  },
  inputDevice: { id: 'chat.voice.input_device', defaultMessage: 'Microphone' },
  outputDevice: { id: 'chat.voice.output_device', defaultMessage: 'Speaker' },
  systemDefault: {
    id: 'chat.voice.system_default',
    defaultMessage: 'System default',
  },
  echoCancellation: {
    id: 'chat.voice.echo_cancellation',
    defaultMessage: 'Echo cancellation',
  },
  noiseSuppression: {
    id: 'chat.voice.noise_suppression',
    defaultMessage: 'Noise suppression',
  },
  autoGainControl: {
    id: 'chat.voice.auto_gain_control',
    defaultMessage: 'Automatic volume adjustment',
  },
  screenShareQuality: {
    id: 'chat.voice.screen_share_quality',
    defaultMessage: 'Screen share quality',
  },
  qualitySharp: {
    id: 'chat.voice.quality.sharp',
    defaultMessage: 'Sharp text (1080p, 15 fps)',
  },
  qualitySmooth: {
    id: 'chat.voice.quality.smooth',
    defaultMessage: 'Smooth motion (720p, 30 fps)',
  },
  qualityHigh: {
    id: 'chat.voice.quality.high',
    defaultMessage: 'High quality (1080p, 30 fps)',
  },
  screenShareAudio: {
    id: 'chat.voice.screen_share_audio',
    defaultMessage: 'Share audio with the screen',
  },
  close: { id: 'chat.voice.close', defaultMessage: 'Close' },
  mediaNoticeTitle: {
    id: 'chat.voice.media_notice.title',
    defaultMessage: 'Connect to the call server?',
  },
  mediaNotice: {
    id: 'chat.voice.media_notice.message',
    defaultMessage:
      'Calls on this server are carried by {host}. Your IP address will be visible to that server while you are in a call.',
  },
  mediaNoticeConfirm: {
    id: 'chat.voice.media_notice.confirm',
    defaultMessage: 'Join call',
  },
  switchCallTitle: {
    id: 'chat.voice.switch.title',
    defaultMessage: 'Switch calls?',
  },
  switchCall: {
    id: 'chat.voice.switch.message',
    defaultMessage: 'You will leave the call you are in now.',
  },
  switchCallConfirm: {
    id: 'chat.voice.switch.confirm',
    defaultMessage: 'Switch',
  },
  errorUnavailable: {
    id: 'chat.voice.error.unavailable',
    defaultMessage: 'Voice calls are not available in this chat.',
  },
  errorBusy: {
    id: 'chat.voice.error.busy',
    defaultMessage: 'The call is being set up or closed. Try again shortly.',
  },
  errorFull: {
    id: 'chat.voice.error.full',
    defaultMessage: 'The call server has no room for another call right now.',
  },
  errorRevoked: {
    id: 'chat.voice.error.revoked',
    defaultMessage:
      'This server can no longer use its call server. Contact an administrator.',
  },
  errorUnreachable: {
    id: 'chat.voice.error.unreachable',
    defaultMessage: 'Could not reach the call server.',
  },
  errorRemoteUnsupported: {
    id: 'chat.voice.error.remote_unsupported',
    defaultMessage:
      'The server that owns this room does not offer voice calls.',
  },
  errorRemoteUnreachable: {
    id: 'chat.voice.error.remote_unreachable',
    defaultMessage:
      'Could not get a call token from the server that owns this room.',
  },
  errorRemoved: {
    id: 'chat.voice.error.removed',
    defaultMessage:
      'You were removed from this call. Try again in a few minutes.',
  },
  errorRateLimited: {
    id: 'chat.voice.error.rate_limited',
    defaultMessage: 'Too many call requests. Wait a moment and try again.',
  },
  connectionFailed: {
    id: 'chat.voice.error.connection_failed',
    defaultMessage: 'Could not connect to the call.',
  },
  micUnavailable: {
    id: 'chat.voice.error.mic_unavailable',
    defaultMessage:
      'The microphone could not be used. You can still listen to the call.',
  },
  screenShareFailed: {
    id: 'chat.voice.error.screen_share_failed',
    defaultMessage: 'Could not share the screen.',
  },
  screenSharePermissionDenied: {
    id: 'chat.voice.error.screen_share_denied',
    defaultMessage: 'The browser did not allow screen sharing.',
  },
  joinedElsewhere: {
    id: 'chat.voice.ended.elsewhere',
    defaultMessage: 'You joined this call from another tab or device.',
  },
  removedFromCall: {
    id: 'chat.voice.ended.removed',
    defaultMessage: 'You were removed from the call.',
  },
  callEnded: { id: 'chat.voice.ended.call', defaultMessage: 'The call ended.' },
  disconnected: {
    id: 'chat.voice.ended.disconnected',
    defaultMessage: 'The call was disconnected.',
  },
});
