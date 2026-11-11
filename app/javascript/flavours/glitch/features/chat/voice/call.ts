import { useSyncExternalStore } from 'react';

import type { MessageDescriptor } from 'react-intl';

import { isAxiosError } from 'axios';
import type * as LK from 'livekit-client';

import { showAlert } from 'flavours/glitch/actions/alerts';
import { store } from 'flavours/glitch/store';

import {
  reportVoiceStatus,
  requestVoiceCredentials,
  voiceErrorCode,
} from './api';
import type {
  ScreenShareLimits,
  VoiceCredentials,
  VoiceErrorCode,
} from './api';
import { voiceMessages } from './messages';
import {
  participantVolume,
  setStoredParticipantVolume,
  updateVoicePreferences,
  voicePreferences,
} from './preferences';
import type { ParticipantAudio, ScreenShareQuality } from './preferences';

type LiveKit = typeof LK;

export type VoiceCallStatus =
  | 'idle'
  | 'connecting'
  | 'connected'
  | 'reconnecting';

export interface VoiceCallConversation {
  id: string;
  title: string;
}

export interface VoiceCallSnapshot {
  status: VoiceCallStatus;
  conversation: VoiceCallConversation | null;
  identity: string | null;
  mediaProvider: string | null;
  allowScreenShare: boolean;
  micEnabled: boolean;
  deafened: boolean;
  audioBlocked: boolean;
  speakingIdentities: string[];
  screenSharing: boolean;
  screenShareIdentities: string[];
  watchingIdentities: string[];
}

const IDLE: VoiceCallSnapshot = {
  status: 'idle',
  conversation: null,
  identity: null,
  mediaProvider: null,
  allowScreenShare: false,
  micEnabled: false,
  deafened: false,
  audioBlocked: false,
  speakingIdentities: [],
  screenSharing: false,
  screenShareIdentities: [],
  watchingIdentities: [],
};

let state: VoiceCallSnapshot = IDLE;
const listeners = new Set<() => void>();

const setState = (changes: Partial<VoiceCallSnapshot>) => {
  state = { ...state, ...changes };
  listeners.forEach((listener) => {
    listener();
  });
};

export const voiceCallSnapshot = () => state;

export const subscribeVoiceCall = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

export const useVoiceCall = () =>
  useSyncExternalStore(subscribeVoiceCall, voiceCallSnapshot);

const notice = (message: MessageDescriptor) => {
  store.dispatch(showAlert({ message }));
};

export const voiceErrorMessage = (code: VoiceErrorCode) => {
  switch (code) {
    case 'VOICE_CALL_UNAVAILABLE':
      return voiceMessages.errorUnavailable;
    case 'VOICE_CALL_BUSY':
      return voiceMessages.errorBusy;
    case 'VOICE_RELAY_CAPACITY_EXCEEDED':
      return voiceMessages.errorFull;
    case 'VOICE_RELAY_REVOKED':
      return voiceMessages.errorRevoked;
    case 'VOICE_RELAY_UNREACHABLE':
      return voiceMessages.errorUnreachable;
    case 'REMOTE_HOST_UNSUPPORTED':
      return voiceMessages.errorRemoteUnsupported;
    case 'REMOTE_HOST_UNREACHABLE':
      return voiceMessages.errorRemoteUnreachable;
    case 'RATE_LIMITED':
      return voiceMessages.errorRateLimited;
    default:
      return voiceMessages.connectionFailed;
  }
};

export const notifyVoiceCallFailure = (error?: unknown) => {
  notice(voiceErrorMessage(voiceErrorCode(error)));
};

let livekit: LiveKit | null = null;
let current: LK.Room | null = null;
let screenShareLimits: ScreenShareLimits | null = null;
let pendingScreenShare: { room: LK.Room; promise: Promise<void> } | null = null;
let joinAttempt = 0;
let leaveRevision = 0;

export const voiceLeaveRevision = () => leaveRevision;
let deafenRevision = 0;

const loadLiveKit = async () => {
  livekit ??= await import('livekit-client');
  return livekit;
};

const ICE_REFRESH_INTERVAL_MS = 6 * 60 * 60 * 1000;
const ICE_REFRESH_STALE_MS = 60 * 60 * 1000;
const ICE_REFRESH_RETRY_MS = 60 * 1000;

interface IceRefresh {
  room: LK.Room;
  conversationId: string;
  url: string;
  mediaProvider: string;
  lastSuccess: number;
  retryDelay: number;
  timer: number | null;
  inFlight: boolean;
  iceServers: RTCIceServer[];
}

let iceRefresh: IceRefresh | null = null;

const stopIceRefresh = () => {
  if (iceRefresh?.timer != null) window.clearTimeout(iceRefresh.timer);
  iceRefresh = null;
};

const scheduleIceRefresh = (refresh: IceRefresh, delay: number) => {
  if (iceRefresh !== refresh || current !== refresh.room) return;
  if (refresh.timer != null) window.clearTimeout(refresh.timer);
  refresh.timer = window.setTimeout(() => {
    refresh.timer = null;
    void refreshIceServers(refresh);
  }, delay);
};

interface PeerTransport {
  _pc?: RTCPeerConnection;
}

const refreshIceServers = async (refresh: IceRefresh) => {
  if (iceRefresh !== refresh || current !== refresh.room || refresh.inFlight)
    return;
  refresh.inFlight = true;
  let nextDelay = refresh.retryDelay;
  try {
    const credentials = await requestVoiceCredentials(refresh.conversationId);
    if (iceRefresh !== refresh || current !== refresh.room) return;
    if (
      credentials.url !== refresh.url ||
      credentials.media_provider !== refresh.mediaProvider
    ) {
      stopIceRefresh();
      return;
    }
    if (credentials.ice_servers == null) throw new Error('No ICE servers');
    const iceServers = credentials.ice_servers;
    const engine = refresh.room.engine;
    const changed =
      JSON.stringify(iceServers) !== JSON.stringify(refresh.iceServers);
    if (changed) {
      const manager = engine.pcManager;
      for (const transport of [manager?.publisher, manager?.subscriber]) {
        const pc = (transport as PeerTransport | undefined)?._pc;
        if (pc && pc.connectionState !== 'closed')
          pc.setConfiguration({ ...pc.getConfiguration(), iceServers });
      }
      engine.rtcConfig.iceServers = iceServers;
    }
    if (changed || state.status === 'reconnecting')
      (engine as unknown as { token: string }).token = credentials.token;
    if (changed) {
      const manager = engine.pcManager;
      if (state.status === 'reconnecting' && manager)
        await manager.triggerIceRestart();
      else if (state.status === 'connected') engine.reconnect();
      refresh.iceServers = iceServers;
    }
    refresh.lastSuccess = Date.now();
    refresh.retryDelay = ICE_REFRESH_RETRY_MS;
    nextDelay = ICE_REFRESH_INTERVAL_MS;
  } catch {
    refresh.retryDelay = Math.min(refresh.retryDelay * 2, ICE_REFRESH_STALE_MS);
  } finally {
    refresh.inFlight = false;
    scheduleIceRefresh(refresh, nextDelay);
  }
};

const startIceRefresh = (
  room: LK.Room,
  conversationId: string,
  credentials: VoiceCredentials,
) => {
  stopIceRefresh();
  const iceServers = credentials.ice_servers;
  if (
    !iceServers?.some((server) =>
      server.urls.some((value) => /^turns?:/i.test(value)),
    )
  )
    return;
  iceRefresh = {
    room,
    conversationId,
    url: credentials.url,
    mediaProvider: credentials.media_provider,
    lastSuccess: Date.now(),
    retryDelay: ICE_REFRESH_RETRY_MS,
    timer: null,
    inFlight: false,
    iceServers,
  };
  scheduleIceRefresh(iceRefresh, ICE_REFRESH_INTERVAL_MS);
};

interface StatusReport {
  session_id: string;
  mic_muted: boolean;
  deafened: boolean;
}

interface StatusDelivery {
  room: LK.Room;
  conversationId: string;
  latest: StatusReport;
  pending: StatusReport | null;
  sending: boolean;
  retryDelay: number;
  timer: number | null;
  stopped: boolean;
}

let statusDelivery: StatusDelivery | null = null;

const resetStatusDelivery = () => {
  if (statusDelivery?.timer != null) window.clearTimeout(statusDelivery.timer);
  statusDelivery = null;
};

const isTransientStatusError = (error: unknown) => {
  if (!isAxiosError(error)) return true;
  const status = error.response?.status;
  return status == null || status === 429 || status >= 500;
};

const hasPendingStatus = (delivery: StatusDelivery) => delivery.pending != null;

const deliverStatus = async (delivery: StatusDelivery): Promise<void> => {
  if (
    statusDelivery !== delivery ||
    current !== delivery.room ||
    delivery.sending ||
    delivery.timer != null ||
    delivery.stopped ||
    delivery.pending == null
  )
    return;
  const status = delivery.pending;
  delivery.pending = null;
  delivery.sending = true;
  try {
    await reportVoiceStatus(delivery.conversationId, status);
    delivery.retryDelay = 1000;
  } catch (error) {
    if (statusDelivery !== delivery || current !== delivery.room) return;
    if (!isTransientStatusError(error)) {
      if (!hasPendingStatus(delivery)) {
        delivery.stopped = true;
        return;
      }
    } else {
      delivery.pending ??= status;
      const rateLimited = isAxiosError(error) && error.response?.status === 429;
      const delay = rateLimited ? 60_000 : delivery.retryDelay;
      delivery.retryDelay = Math.min(delivery.retryDelay * 2, 30_000);
      delivery.timer = window.setTimeout(() => {
        delivery.timer = null;
        void deliverStatus(delivery);
      }, delay);
    }
  } finally {
    delivery.sending = false;
  }
  if (statusDelivery === delivery) void deliverStatus(delivery);
};

const reportStatus = (room: LK.Room, force = false) => {
  const conversationId = state.conversation?.id;
  const sessionId = room.localParticipant.sid;
  if (
    current !== room ||
    !conversationId ||
    !sessionId ||
    state.status === 'connecting'
  )
    return;
  const status: StatusReport = {
    session_id: sessionId,
    mic_muted: !state.micEnabled,
    deafened: state.deafened,
  };
  if (
    statusDelivery?.room !== room ||
    statusDelivery.latest.session_id !== status.session_id
  ) {
    resetStatusDelivery();
    statusDelivery = {
      room,
      conversationId,
      latest: status,
      pending: status,
      sending: false,
      retryDelay: 1000,
      timer: null,
      stopped: false,
    };
  } else {
    if (
      !force &&
      statusDelivery.latest.mic_muted === status.mic_muted &&
      statusDelivery.latest.deafened === status.deafened
    )
      return;
    statusDelivery.stopped = false;
    statusDelivery.latest = status;
    statusDelivery.pending = status;
  }
  void deliverStatus(statusDelivery);
};

let stopLocalMeter: (() => void) | null = null;
let localMeterContext: BaseAudioContext | null = null;
const unmeterableTracks = new WeakSet<MediaStreamTrack>();
let watchedMicrophoneTrack: LK.LocalAudioTrack | null = null;
let unwatchMicrophoneTrack: (() => void) | null = null;

const setLocalSpeaking = (room: LK.Room, speaking: boolean) => {
  const identity = room.localParticipant.identity;
  if (state.speakingIdentities.includes(identity) === speaking) return;
  setState({
    speakingIdentities: speaking
      ? [...state.speakingIdentities, identity]
      : state.speakingIdentities.filter((id) => id !== identity),
  });
};

const watchMicrophoneTrack = (room: LK.Room, track: LK.LocalAudioTrack) => {
  if (livekit == null || watchedMicrophoneTrack === track) return;
  unwatchMicrophoneTrack?.();
  const events = livekit.TrackEvent;
  const onRestarted = () => {
    if (current === room) startLocalMeter(room);
  };
  const onEnded = () => {
    stopLocalMeter?.();
  };
  track.on(events.Restarted, onRestarted);
  track.on(events.Ended, onEnded);
  watchedMicrophoneTrack = track;
  unwatchMicrophoneTrack = () => {
    track.off(events.Restarted, onRestarted);
    track.off(events.Ended, onEnded);
    watchedMicrophoneTrack = null;
    unwatchMicrophoneTrack = null;
  };
};

const startLocalMeter = (room: LK.Room) => {
  stopLocalMeter?.();
  if (livekit == null || current !== room || !state.micEnabled) return;
  const track = room.localParticipant.getTrackPublication(
    livekit.Track.Source.Microphone,
  )?.track;
  if (track?.kind !== livekit.Track.Kind.Audio) return;
  watchMicrophoneTrack(room, track as LK.LocalAudioTrack);
  if (unmeterableTracks.has(track.mediaStreamTrack)) return;
  try {
    const meter = livekit.createAudioAnalyser(track as LK.LocalAudioTrack, {
      fftSize: 512,
    });
    const context = meter.analyser.context;
    const samples = new Float32Array(meter.analyser.fftSize);
    let lastLoudAt = -Infinity;
    const timer = window.setInterval(() => {
      if (
        current !== room ||
        !state.micEnabled ||
        context.state === 'suspended'
      )
        return;
      meter.analyser.getFloatTimeDomainData(samples);
      const rms = Math.sqrt(
        samples.reduce((sum, value) => sum + value * value, 0) / samples.length,
      );
      if (rms >= 0.02) lastLoudAt = Date.now();
      setLocalSpeaking(room, Date.now() - lastLoudAt < 150);
    }, 50);
    localMeterContext = context;
    stopLocalMeter = () => {
      window.clearInterval(timer);
      void meter.cleanup().catch(() => undefined);
      setLocalSpeaking(room, false);
      stopLocalMeter = null;
      localMeterContext = null;
    };
  } catch {
    unmeterableTracks.add(track.mediaStreamTrack);
  }
};

interface ScreenShareView {
  element: HTMLVideoElement;
  preview: boolean;
}

const screenShareTracks = new Map<string, LK.RemoteTrack | LK.LocalTrack>();
const screenShareViews = new Map<string, Set<ScreenShareView>>();

const SCREEN_SHARE_PREVIEW_LAYER = {
  width: 320,
  height: 180,
  maxBitrate: 100_000,
  maxFramerate: 5,
  priority: 'medium',
} as const;

const SCREEN_SHARE_PICKER_MIN_MS = 250;
const SCREEN_SHARE_SOURCE = 3;

const captureOptions = (): LK.AudioCaptureOptions => {
  const preferences = voicePreferences();
  return {
    deviceId: preferences.inputDeviceId ?? undefined,
    echoCancellation: preferences.echoCancellation,
    noiseSuppression: preferences.noiseSuppression,
    autoGainControl: preferences.autoGainControl,
  };
};

const processingOf = (options: LK.AudioCaptureOptions) =>
  JSON.stringify([
    options.echoCancellation,
    options.noiseSuppression,
    options.autoGainControl,
  ]);

let microphoneProcessing: string | null = null;

const microphoneTrackOf = (room: LK.Room) => {
  if (livekit == null) return undefined;
  const track = room.localParticipant.getTrackPublication(
    livekit.Track.Source.Microphone,
  )?.track;
  return track?.kind === livekit.Track.Kind.Audio
    ? (track as LK.LocalAudioTrack)
    : undefined;
};

const volumeOf = (identity: string, audio: ParticipantAudio) =>
  state.deafened ? 0 : participantVolume(identity, audio);

const applyVolume = (participant: LK.RemoteParticipant) => {
  if (livekit == null) return;
  const { Track } = livekit;
  participant.setVolume(
    volumeOf(participant.identity, 'voice'),
    Track.Source.Microphone,
  );
  participant.setVolume(
    volumeOf(participant.identity, 'screenShare'),
    Track.Source.ScreenShareAudio,
  );
};

const applyVolumes = (room: LK.Room) => {
  room.remoteParticipants.forEach(applyVolume);
};

const disableMicrophone = async (room: LK.Room) => {
  await room.localParticipant.setMicrophoneEnabled(false, captureOptions());
  if (current !== room) return;
  setState({ micEnabled: false });
  stopLocalMeter?.();
  unwatchMicrophoneTrack?.();
  reportStatus(room);
};

const enableMicrophone = async (
  room: LK.Room,
  undeafenAt: number | null = null,
) => {
  try {
    const options = captureOptions();
    const existing = microphoneTrackOf(room);
    await room.localParticipant.setMicrophoneEnabled(true, options);
    if (current !== room) return;
    if (existing != null && microphoneProcessing !== processingOf(options))
      await existing.restartTrack(options);
    microphoneProcessing = processingOf(options);
    if (current !== room) return;
    setState({ micEnabled: true });
    if (undeafenAt != null && undeafenAt === deafenRevision && state.deafened) {
      setState({ deafened: false });
      applyVolumes(room);
    }
    if (state.deafened) {
      await disableMicrophone(room).catch(() => {
        reportStatus(room);
      });
      return;
    }
    startLocalMeter(room);
    reportStatus(room);
  } catch {
    if (current !== room) return;
    setState({ micEnabled: false });
    stopLocalMeter?.();
    reportStatus(room);
    notice(voiceMessages.micUnavailable);
  }
};

const screenSharePublicationOf = (room: LK.Room, identity: string) => {
  const participant = room.remoteParticipants.get(identity);
  if (participant == null || livekit == null) return undefined;
  for (const publication of participant.trackPublications.values()) {
    if (publication.source === livekit.Track.Source.ScreenShare)
      return publication;
  }
  return undefined;
};

const isScreenSharePreviewed = (identity: string) => {
  for (const view of screenShareViews.get(identity) ?? []) {
    if (view.preview) return true;
  }
  return false;
};

const hasLowerLayer = (publication: LK.RemoteTrackPublication) => {
  const layerCount = Math.max(
    0,
    ...(publication.trackInfo?.codecs ?? []).map(
      (codec) => codec.layers.length,
    ),
  );
  if (layerCount > 0) return layerCount >= 2;
  return publication.simulcasted === true;
};

const syncScreenShareSubscription = (identity: string) => {
  if (current == null || livekit == null) return;
  const watched = state.watchingIdentities.includes(identity);
  for (const publication of current.remoteParticipants
    .get(identity)
    ?.trackPublications.values() ?? []) {
    if (publication.source === livekit.Track.Source.ScreenShareAudio)
      publication.setSubscribed(watched);
  }
  const publication = screenSharePublicationOf(current, identity);
  if (publication == null) return;
  if (
    !watched &&
    !(isScreenSharePreviewed(identity) && hasLowerLayer(publication))
  ) {
    if (publication.isDesired) publication.setSubscribed(false);
    return;
  }
  if (!publication.isDesired) publication.setSubscribed(true);
  publication.setVideoQuality(
    watched ? livekit.VideoQuality.HIGH : livekit.VideoQuality.LOW,
  );
};

const forgetScreenShare = (identity: string) => {
  screenShareTracks.delete(identity);
  setState({
    screenShareIdentities: state.screenShareIdentities.filter(
      (x) => x !== identity,
    ),
    watchingIdentities: state.watchingIdentities.filter((x) => x !== identity),
  });
  syncScreenShareSubscription(identity);
};

const releaseScreenShare = (identity: string) => {
  if (state.status === 'reconnecting') screenShareTracks.delete(identity);
  else forgetScreenShare(identity);
};

const pruneScreenShares = (room: LK.Room) => {
  const sharing = (identity: string) =>
    screenSharePublicationOf(room, identity) != null;
  for (const identity of state.screenShareIdentities) {
    if (!sharing(identity)) screenShareTracks.delete(identity);
  }
  setState({
    screenShareIdentities: state.screenShareIdentities.filter(sharing),
    watchingIdentities: state.watchingIdentities.filter(sharing),
  });
};

const applySubscription = (
  lk: LiveKit,
  publication: LK.TrackPublication,
  participant: LK.RemoteParticipant,
) => {
  const remote = publication as LK.RemoteTrackPublication;
  switch (publication.source) {
    case lk.Track.Source.Microphone:
      remote.setSubscribed(true);
      break;
    case lk.Track.Source.ScreenShareAudio:
      remote.setSubscribed(
        state.watchingIdentities.includes(participant.identity),
      );
      break;
    case lk.Track.Source.ScreenShare:
      if (!state.screenShareIdentities.includes(participant.identity))
        setState({
          screenShareIdentities: [
            ...state.screenShareIdentities,
            participant.identity,
          ],
        });
      syncScreenShareSubscription(participant.identity);
      break;
    default:
      remote.setSubscribed(false);
  }
};

const detachLocalScreenShare = (identity: string) => {
  const track = screenShareTracks.get(identity);
  if (track == null) return;
  for (const view of screenShareViews.get(identity) ?? [])
    track.detach(view.element);
};

const detachAll = (room: LK.Room) => {
  detachLocalScreenShare(room.localParticipant.identity);
  for (const participant of room.remoteParticipants.values()) {
    for (const publication of participant.trackPublications.values()) {
      const track = publication.track;
      if (track == null) continue;
      const elements = track.detach();
      if (track.kind === livekit?.Track.Kind.Audio)
        elements.forEach((element) => {
          element.remove();
        });
    }
  }
};

const resetState = () => {
  stopIceRefresh();
  resetStatusDelivery();
  stopLocalMeter?.();
  unwatchMicrophoneTrack?.();
  screenShareTracks.clear();
  screenShareLimits = null;
  setState(IDLE);
};

const disconnectMessage = (
  lk: LiveKit,
  reason: LK.DisconnectReason | undefined,
) => {
  switch (reason) {
    case lk.DisconnectReason.CLIENT_INITIATED:
      return null;
    case lk.DisconnectReason.DUPLICATE_IDENTITY:
      return voiceMessages.joinedElsewhere;
    case lk.DisconnectReason.PARTICIPANT_REMOVED:
      return voiceMessages.removedFromCall;
    case lk.DisconnectReason.ROOM_DELETED:
      return voiceMessages.callEnded;
    default:
      return voiceMessages.disconnected;
  }
};

const bindRoomEvents = (lk: LiveKit, room: LK.Room) => {
  const { RoomEvent, Track } = lk;
  const isCurrent = () => current === room;

  room.on(
    RoomEvent.TrackPublished,
    (
      publication: LK.RemoteTrackPublication,
      participant: LK.RemoteParticipant,
    ) => {
      if (isCurrent()) applySubscription(lk, publication, participant);
    },
  );

  room.on(
    RoomEvent.TrackSubscribed,
    (
      track: LK.RemoteTrack,
      publication: LK.RemoteTrackPublication,
      participant: LK.RemoteParticipant,
    ) => {
      if (!isCurrent()) return;
      if (track.kind === Track.Kind.Audio) {
        document.body.appendChild(track.attach());
        applyVolume(participant);
      } else if (publication.source === Track.Source.ScreenShare) {
        screenShareTracks.set(participant.identity, track);
        for (const view of screenShareViews.get(participant.identity) ?? [])
          track.attach(view.element);
      }
    },
  );

  room.on(
    RoomEvent.TrackUnsubscribed,
    (
      track: LK.RemoteTrack,
      publication: LK.RemoteTrackPublication,
      participant: LK.RemoteParticipant,
    ) => {
      if (track.kind === Track.Kind.Audio) {
        track.detach().forEach((element) => {
          element.remove();
        });
      } else if (publication.source === Track.Source.ScreenShare) {
        for (const view of screenShareViews.get(participant.identity) ?? [])
          track.detach(view.element);
        screenShareTracks.delete(participant.identity);
      }
    },
  );

  room.on(
    RoomEvent.TrackUnpublished,
    (
      publication: LK.RemoteTrackPublication,
      participant: LK.RemoteParticipant,
    ) => {
      if (isCurrent() && publication.source === Track.Source.ScreenShare)
        releaseScreenShare(participant.identity);
    },
  );

  room.on(
    RoomEvent.ParticipantDisconnected,
    (participant: LK.RemoteParticipant) => {
      if (isCurrent()) releaseScreenShare(participant.identity);
    },
  );

  room.on(
    RoomEvent.LocalTrackPublished,
    (
      publication: LK.LocalTrackPublication,
      participant: LK.LocalParticipant,
    ) => {
      const track = publication.track;
      if (!isCurrent()) return;
      if (publication.source === Track.Source.Microphone) {
        startLocalMeter(room);
        return;
      }
      if (publication.source !== Track.Source.ScreenShare || track == null)
        return;
      setState({ screenSharing: true });
      screenShareTracks.set(participant.identity, track);
      for (const view of screenShareViews.get(participant.identity) ?? [])
        track.attach(view.element);
    },
  );

  room.on(
    RoomEvent.LocalTrackUnpublished,
    (
      publication: LK.LocalTrackPublication,
      participant: LK.LocalParticipant,
    ) => {
      if (!isCurrent() || publication.source !== Track.Source.ScreenShare)
        return;
      setState({ screenSharing: false });
      detachLocalScreenShare(participant.identity);
      forgetScreenShare(participant.identity);
    },
  );

  room.on(
    RoomEvent.TrackMuted,
    (publication: LK.TrackPublication, participant: LK.Participant) => {
      if (!isCurrent()) return;
      if (
        participant === room.localParticipant &&
        publication.source === Track.Source.Microphone
      ) {
        setState({ micEnabled: false });
        stopLocalMeter?.();
        reportStatus(room);
      }
    },
  );

  room.on(
    RoomEvent.ParticipantPermissionsChanged,
    (_previous: unknown, participant: LK.Participant) => {
      if (!isCurrent() || participant !== room.localParticipant) return;
      const sources: readonly number[] =
        participant.permissions?.canPublishSources ?? [];
      const allowed =
        sources.length === 0 || sources.includes(SCREEN_SHARE_SOURCE);
      if (allowed === state.allowScreenShare) return;
      setState({ allowScreenShare: allowed });
      if (
        !allowed &&
        (state.screenSharing || pendingScreenShare?.room === room)
      )
        void stopScreenShare().catch(() => undefined);
    },
  );

  room.on(RoomEvent.ActiveSpeakersChanged, (speakers: LK.Participant[]) => {
    if (!isCurrent()) return;
    const localIdentity = room.localParticipant.identity;
    const others = speakers
      .filter((speaker) => speaker.identity !== localIdentity)
      .map((speaker) => speaker.identity);
    const metered =
      stopLocalMeter != null && localMeterContext?.state !== 'suspended';
    const localSpeaking = metered
      ? state.speakingIdentities.includes(localIdentity)
      : speakers.some((speaker) => speaker.identity === localIdentity);
    setState({
      speakingIdentities: localSpeaking ? [...others, localIdentity] : others,
    });
  });

  room.on(RoomEvent.AudioPlaybackStatusChanged, () => {
    if (isCurrent()) setState({ audioBlocked: !room.canPlaybackAudio });
  });

  room.on(RoomEvent.Reconnecting, () => {
    if (!isCurrent()) return;
    setState({ status: 'reconnecting' });
    const refresh = iceRefresh;
    if (
      refresh?.room === room &&
      Date.now() - refresh.lastSuccess >= ICE_REFRESH_STALE_MS
    ) {
      if (refresh.timer != null) window.clearTimeout(refresh.timer);
      refresh.timer = null;
      void refreshIceServers(refresh);
    }
  });

  room.on(RoomEvent.Reconnected, () => {
    if (!isCurrent()) return;
    pruneScreenShares(room);
    setState({ status: 'connected' });
    reportStatus(room, true);
    startLocalMeter(room);
  });

  room.on(RoomEvent.Disconnected, (reason?: LK.DisconnectReason) => {
    if (!isCurrent()) return;
    current = null;
    joinAttempt++;
    detachAll(room);
    resetState();
    const message = disconnectMessage(lk, reason);
    if (message != null) notice(message);
  });
};

const disconnectCurrentRoom = async () => {
  const room = current;
  current = null;
  stopIceRefresh();
  if (room != null) {
    await room.disconnect();
    detachAll(room);
  }
};

export const prepareVoiceCall = () => loadLiveKit();

export const connectVoiceCall = async (
  conversation: VoiceCallConversation,
  credentials: VoiceCredentials,
  options: { micEnabled?: boolean } = {},
) => {
  const attempt = ++joinAttempt;
  if (current != null) {
    await disconnectCurrentRoom();
    if (attempt !== joinAttempt) return;
  }

  resetState();
  setState({
    status: 'connecting',
    conversation,
    identity: credentials.identity,
    mediaProvider: credentials.media_provider,
    allowScreenShare: credentials.allow_screen_share,
  });

  let lk: LiveKit;
  try {
    lk = await loadLiveKit();
  } catch (error) {
    if (attempt === joinAttempt) {
      resetState();
      notifyVoiceCallFailure(error);
    }
    return;
  }
  if (attempt !== joinAttempt) return;

  screenShareLimits = credentials.screen_share_limits;
  const room = new lk.Room({ adaptiveStream: true, dynacast: true });
  current = room;
  bindRoomEvents(lk, room);

  const connectOptions: LK.RoomConnectOptions =
    credentials.ice_servers != null
      ? {
          autoSubscribe: false,
          rtcConfig: { iceServers: credentials.ice_servers },
        }
      : { autoSubscribe: false };

  try {
    await room.connect(credentials.url, credentials.token, connectOptions);
  } catch {
    if (current === room) {
      current = null;
      resetState();
      notice(voiceMessages.connectionFailed);
    }
    return;
  }
  if (current !== room) return;

  setState({ status: 'connected', audioBlocked: !room.canPlaybackAudio });
  startIceRefresh(room, conversation.id, credentials);

  for (const participant of room.remoteParticipants.values()) {
    for (const publication of participant.trackPublications.values())
      applySubscription(lk, publication, participant);
  }

  const outputDeviceId = voicePreferences().outputDeviceId;
  if (outputDeviceId != null)
    room
      .switchActiveDevice('audiooutput', outputDeviceId)
      .catch(() => undefined);

  if ((options.micEnabled ?? voicePreferences().micEnabled) && !state.deafened)
    await enableMicrophone(room);
  else reportStatus(room);
};

export const leaveVoiceCall = async () => {
  leaveRevision++;
  const attempt = ++joinAttempt;
  await disconnectCurrentRoom();
  if (attempt === joinAttempt) resetState();
};

export const setMicEnabled = async (enabled: boolean) => {
  const room = current;
  if (room == null) return;
  updateVoicePreferences({ micEnabled: enabled });
  if (enabled)
    await enableMicrophone(room, state.deafened ? deafenRevision : null);
  else await disableMicrophone(room);
};

export const restartMicrophone = async () => {
  const room = current;
  if (room == null || !state.micEnabled) return;
  const track = microphoneTrackOf(room);
  if (track == null) return;
  const options = captureOptions();
  await track.restartTrack(options);
  microphoneProcessing = processingOf(options);
};

export const setDeafened = (deafened: boolean) => {
  deafenRevision++;
  setState({ deafened });
  const room = current;
  if (room == null) return;
  applyVolumes(room);
  if (deafened && state.micEnabled) {
    disableMicrophone(room).catch(() => {
      reportStatus(room);
    });
    return;
  }
  reportStatus(room);
};

export const resumeAudio = async () => {
  const room = current;
  if (room == null) return;
  await room.startAudio();
  setState({ audioBlocked: !room.canPlaybackAudio });
};

export const setParticipantVolume = (
  identity: string,
  audio: ParticipantAudio,
  volume: number,
) => {
  setStoredParticipantVolume(identity, audio, volume);
  const participant = current?.remoteParticipants.get(identity);
  if (participant != null) applyVolume(participant);
};

export const activeAudioDeviceId = (kind: 'audioinput' | 'audiooutput') => {
  const preferences = voicePreferences();
  return (
    (kind === 'audioinput'
      ? preferences.inputDeviceId
      : preferences.outputDeviceId) ??
    current?.getActiveDevice(kind) ??
    'default'
  );
};

export const selectAudioDevice = async (
  kind: 'audioinput' | 'audiooutput',
  deviceId: string,
) => {
  updateVoicePreferences(
    kind === 'audioinput'
      ? { inputDeviceId: deviceId }
      : { outputDeviceId: deviceId },
  );
  const room = current;
  if (room == null) return;
  await room.switchActiveDevice(kind, deviceId);
  if (kind === 'audioinput' && current === room) startLocalMeter(room);
};

export const listAudioDevices = async (kind: 'audioinput' | 'audiooutput') => {
  const lk = await loadLiveKit();
  return lk.Room.getLocalDevices(kind, false);
};

export const canShareScreen = () => {
  const devices = window.navigator.mediaDevices as MediaDevices | undefined;
  return typeof devices?.getDisplayMedia === 'function';
};

const screenSharePreset = (
  lk: LiveKit,
  quality: ScreenShareQuality,
): { preset: LK.VideoPreset; contentHint: 'detail' | 'motion' } => {
  switch (quality) {
    case 'smooth':
      return { preset: lk.ScreenSharePresets.h720fps30, contentHint: 'motion' };
    case 'high':
      return {
        preset: lk.ScreenSharePresets.h1080fps30,
        contentHint: 'motion',
      };
    default:
      return {
        preset: lk.ScreenSharePresets.h1080fps15,
        contentHint: 'detail',
      };
  }
};

const publishLimitedScreenShare = async (
  lk: LiveKit,
  room: LK.Room,
  capture: LK.ScreenShareCaptureOptions,
  publish: LK.TrackPublishOptions,
  limits: ScreenShareLimits,
) => {
  if (room.localParticipant.isScreenShareEnabled) return;
  const tracks = await room.localParticipant.createScreenTracks(capture);
  const published: LK.LocalTrack[] = [];
  try {
    const video = tracks.find(
      (track) => track.source === lk.Track.Source.ScreenShare,
    );
    if (!video) throw new Error('Screen video track missing');
    await video.mediaStreamTrack.applyConstraints({
      width: { max: limits.maxWidth },
      height: { max: limits.maxHeight },
      frameRate: { max: limits.maxFrameRate },
    });
    const settings = video.mediaStreamTrack.getSettings();
    if (
      settings.width == null ||
      settings.height == null ||
      settings.frameRate == null ||
      settings.width > limits.maxWidth ||
      settings.height > limits.maxHeight ||
      settings.frameRate > limits.maxFrameRate
    )
      throw new Error('Screen capture exceeds relay limits');
    if (current !== room) return;
    for (const track of tracks) {
      await room.localParticipant.publishTrack(track, publish);
      published.push(track);
      if (current !== room) throw new Error('Voice call ended');
    }
  } catch (error) {
    await Promise.allSettled(
      published.map((track) => room.localParticipant.unpublishTrack(track)),
    );
    throw error;
  } finally {
    if (published.length !== tracks.length || current !== room)
      tracks.forEach((track) => {
        track.stop();
      });
  }
};

const clearPendingScreenShare = (promise: Promise<void>) => {
  if (pendingScreenShare?.promise === promise) pendingScreenShare = null;
};

export const startScreenShare = async () => {
  const room = current;
  const lk = livekit;
  if (room == null || lk == null || !state.allowScreenShare) return;
  if (pendingScreenShare?.room === room) {
    await pendingScreenShare.promise;
    return;
  }
  const preferences = voicePreferences();
  const { preset, contentHint } = screenSharePreset(
    lk,
    preferences.screenShareQuality,
  );
  const startedAt = Date.now();
  try {
    const capture: LK.ScreenShareCaptureOptions = {
      audio: preferences.screenShareAudio,
      resolution: preset.resolution,
      contentHint,
    };
    const limits = screenShareLimits;
    if (limits) {
      const resolution = {
        width: Math.min(preset.resolution.width, limits.maxWidth),
        height: Math.min(preset.resolution.height, limits.maxHeight),
        frameRate: Math.min(
          preset.resolution.frameRate ?? limits.maxFrameRate,
          limits.maxFrameRate,
        ),
      };
      const promise = publishLimitedScreenShare(
        lk,
        room,
        { ...capture, resolution },
        {
          videoCodec: 'vp8',
          simulcast: false,
          backupCodec: false,
          screenShareEncoding: {
            maxBitrate: Math.min(preset.encoding.maxBitrate, limits.maxBitrate),
            maxFramerate: Math.min(
              preset.encoding.maxFramerate ?? limits.maxFrameRate,
              limits.maxFrameRate,
            ),
          },
        },
        limits,
      );
      pendingScreenShare = { room, promise };
      try {
        await promise;
      } finally {
        clearPendingScreenShare(promise);
      }
    } else {
      await room.localParticipant.setScreenShareEnabled(true, capture, {
        screenShareEncoding: preset.encoding,
        screenShareSimulcastLayers: [
          new lk.VideoPreset(
            SCREEN_SHARE_PREVIEW_LAYER.width,
            SCREEN_SHARE_PREVIEW_LAYER.height,
            SCREEN_SHARE_PREVIEW_LAYER.maxBitrate,
            SCREEN_SHARE_PREVIEW_LAYER.maxFramerate,
            SCREEN_SHARE_PREVIEW_LAYER.priority,
          ),
          lk.ScreenSharePresets.h720fps15,
        ],
      });
    }
    if (current === room)
      setState({ screenSharing: room.localParticipant.isScreenShareEnabled });
  } catch (error) {
    if (current === room) setState({ screenSharing: false });
    if (error instanceof DOMException && error.name === 'NotAllowedError') {
      if (Date.now() - startedAt >= SCREEN_SHARE_PICKER_MIN_MS) return;
      notice(voiceMessages.screenSharePermissionDenied);
      return;
    }
    notice(voiceMessages.screenShareFailed);
  }
};

export const stopScreenShare = async () => {
  const room = current;
  if (room == null) return;
  if (pendingScreenShare?.room === room)
    await pendingScreenShare.promise.catch(() => undefined);
  await room.localParticipant.setScreenShareEnabled(false);
  if (current === room) setState({ screenSharing: false });
};

export const watchScreenShare = (identity: string) => {
  if (state.watchingIdentities.includes(identity)) return;
  setState({ watchingIdentities: [...state.watchingIdentities, identity] });
  syncScreenShareSubscription(identity);
};

export const unwatchScreenShare = (identity: string) => {
  if (!state.watchingIdentities.includes(identity)) return;
  setState({
    watchingIdentities: state.watchingIdentities.filter((x) => x !== identity),
  });
  syncScreenShareSubscription(identity);
};

export const toggleScreenShareWatch = (identity: string) => {
  if (state.watchingIdentities.includes(identity)) unwatchScreenShare(identity);
  else watchScreenShare(identity);
};

export const attachScreenShare = (
  identity: string,
  element: HTMLVideoElement,
  options: { preview?: boolean } = {},
) => {
  const view: ScreenShareView = { element, preview: options.preview === true };
  let views = screenShareViews.get(identity);
  if (views == null) {
    views = new Set();
    screenShareViews.set(identity, views);
  }
  views.add(view);
  screenShareTracks.get(identity)?.attach(element);
  if (view.preview) syncScreenShareSubscription(identity);
  return () => {
    const registered = screenShareViews.get(identity);
    if (!registered?.delete(view)) return;
    if (registered.size === 0) screenShareViews.delete(identity);
    screenShareTracks.get(identity)?.detach(element);
    if (view.preview) syncScreenShareSubscription(identity);
  };
};

export const isInVoiceCall = (conversationId: string | undefined) =>
  conversationId != null &&
  state.conversation?.id === conversationId &&
  state.status !== 'idle';
