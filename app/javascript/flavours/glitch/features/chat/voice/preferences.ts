import { useSyncExternalStore } from 'react';

import { me } from 'flavours/glitch/initial_state';

export type ScreenShareQuality = 'sharp' | 'smooth' | 'high';
export type ParticipantAudio = 'voice' | 'screenShare';

export interface VoicePreferences {
  inputDeviceId: string | null;
  outputDeviceId: string | null;
  echoCancellation: boolean;
  noiseSuppression: boolean;
  autoGainControl: boolean;
  micEnabled: boolean;
  screenShareQuality: ScreenShareQuality;
  screenShareAudio: boolean;
  voiceVolumes: Record<string, number>;
  screenShareVolumes: Record<string, number>;
  acknowledgedMediaProviders: string[];
}

export const DEFAULT_PREFERENCES: VoicePreferences = {
  inputDeviceId: null,
  outputDeviceId: null,
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true,
  micEnabled: true,
  screenShareQuality: 'sharp',
  screenShareAudio: true,
  voiceVolumes: {},
  screenShareVolumes: {},
  acknowledgedMediaProviders: [],
};

const QUALITIES: ScreenShareQuality[] = ['sharp', 'smooth', 'high'];
const MAX_REMEMBERED_VOLUMES = 500;

const storageKey = () => `sharlayan:voice_call:${me ?? 'guest'}`;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

const volumesOf = (value: unknown) => {
  if (!isRecord(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .filter(
        (entry): entry is [string, number] =>
          typeof entry[1] === 'number' && Number.isFinite(entry[1]),
      )
      .map(([identity, volume]) => [identity, clampVolume(volume)]),
  );
};

export const clampVolume = (volume: number) => Math.min(1, Math.max(0, volume));

export const parsePreferences = (raw: string | null): VoicePreferences => {
  let value: unknown = null;
  try {
    value = raw ? JSON.parse(raw) : null;
  } catch {
    value = null;
  }
  if (!isRecord(value)) return { ...DEFAULT_PREFERENCES };

  const text = (key: 'inputDeviceId' | 'outputDeviceId') =>
    typeof value[key] === 'string' ? value[key] : null;
  const flag = (
    key:
      | 'echoCancellation'
      | 'noiseSuppression'
      | 'autoGainControl'
      | 'micEnabled'
      | 'screenShareAudio',
  ) =>
    typeof value[key] === 'boolean' ? value[key] : DEFAULT_PREFERENCES[key];

  return {
    inputDeviceId: text('inputDeviceId'),
    outputDeviceId: text('outputDeviceId'),
    echoCancellation: flag('echoCancellation'),
    noiseSuppression: flag('noiseSuppression'),
    autoGainControl: flag('autoGainControl'),
    micEnabled: flag('micEnabled'),
    screenShareAudio: flag('screenShareAudio'),
    screenShareQuality: QUALITIES.includes(
      value.screenShareQuality as ScreenShareQuality,
    )
      ? (value.screenShareQuality as ScreenShareQuality)
      : DEFAULT_PREFERENCES.screenShareQuality,
    voiceVolumes: volumesOf(value.voiceVolumes),
    screenShareVolumes: volumesOf(value.screenShareVolumes),
    acknowledgedMediaProviders: Array.isArray(value.acknowledgedMediaProviders)
      ? value.acknowledgedMediaProviders.filter(
          (origin): origin is string => typeof origin === 'string',
        )
      : [],
  };
};

const readStorage = () => {
  try {
    return window.localStorage.getItem(storageKey());
  } catch {
    return null;
  }
};

let current: VoicePreferences = parsePreferences(readStorage());
const listeners = new Set<() => void>();

export const voicePreferences = () => current;

export const subscribeVoicePreferences = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

const trimVolumes = (volumes: Record<string, number>) => {
  const entries = Object.entries(volumes);
  return entries.length > MAX_REMEMBERED_VOLUMES
    ? Object.fromEntries(entries.slice(-MAX_REMEMBERED_VOLUMES))
    : volumes;
};

export const updateVoicePreferences = (changes: Partial<VoicePreferences>) => {
  current = {
    ...current,
    ...changes,
    voiceVolumes: trimVolumes(changes.voiceVolumes ?? current.voiceVolumes),
    screenShareVolumes: trimVolumes(
      changes.screenShareVolumes ?? current.screenShareVolumes,
    ),
  };
  writeStorage(JSON.stringify(current));
  listeners.forEach((listener) => {
    listener();
  });
};

const writeStorage = (value: string) => {
  try {
    window.localStorage.setItem(storageKey(), value);
    return true;
  } catch {
    return false;
  }
};

export const participantVolume = (identity: string, audio: ParticipantAudio) =>
  clampVolume(
    (audio === 'voice'
      ? current.voiceVolumes[identity]
      : current.screenShareVolumes[identity]) ?? 1,
  );

export const setStoredParticipantVolume = (
  identity: string,
  audio: ParticipantAudio,
  volume: number,
) => {
  const key = audio === 'voice' ? 'voiceVolumes' : 'screenShareVolumes';
  const rest = Object.fromEntries(
    Object.entries(current[key]).filter(([id]) => id !== identity),
  );
  updateVoicePreferences({
    [key]: { ...rest, [identity]: clampVolume(volume) },
  });
};

export const isMediaProviderAcknowledged = (origin: string) =>
  current.acknowledgedMediaProviders.includes(origin);

export const acknowledgeMediaProvider = (origin: string) => {
  if (isMediaProviderAcknowledged(origin)) return;
  updateVoicePreferences({
    acknowledgedMediaProviders: [...current.acknowledgedMediaProviders, origin],
  });
};

export const useVoicePreferences = () =>
  useSyncExternalStore(subscribeVoicePreferences, voicePreferences);
