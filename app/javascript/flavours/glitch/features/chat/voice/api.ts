import { isAxiosError } from 'axios';

import api from 'flavours/glitch/api';

import type { ChatAccount } from '../account';

export interface VoiceParticipant {
  identity: string;
  account_id: string;
  account: ChatAccount;
  screen_sharing: boolean;
  mic_muted: boolean;
  deafened: boolean;
}

export interface VoiceState {
  conversation_id: string;
  available: boolean;
  active: boolean;
  unavailable: boolean;
  max_participants: number;
  updated_at: number;
  participants: VoiceParticipant[];
}

export interface ScreenShareLimits {
  maxWidth: number;
  maxHeight: number;
  maxFrameRate: number;
  maxBitrate: number;
}

export interface VoiceIceServer {
  urls: string[];
  username?: string;
  credential?: string;
}

export interface VoiceCredentials {
  url: string;
  token: string;
  identity: string;
  media_provider: string;
  ice_servers: VoiceIceServer[] | null;
  screen_share_limits: ScreenShareLimits | null;
  allow_screen_share: boolean;
  max_participants: number;
}

export type VoiceErrorCode =
  | 'VOICE_CALL_UNAVAILABLE'
  | 'VOICE_CALL_BUSY'
  | 'VOICE_RELAY_CAPACITY_EXCEEDED'
  | 'VOICE_RELAY_REVOKED'
  | 'VOICE_RELAY_UNREACHABLE'
  | 'RATE_LIMITED'
  | 'UNKNOWN';

const KNOWN_ERRORS = new Set<string>([
  'VOICE_CALL_UNAVAILABLE',
  'VOICE_CALL_BUSY',
  'VOICE_RELAY_CAPACITY_EXCEEDED',
  'VOICE_RELAY_REVOKED',
  'VOICE_RELAY_UNREACHABLE',
]);

export const voiceErrorCode = (error: unknown): VoiceErrorCode => {
  if (!isAxiosError(error)) return 'UNKNOWN';
  if (error.response?.status === 429) return 'RATE_LIMITED';
  const data: unknown = error.response?.data;
  const code =
    data && typeof data === 'object' && 'error' in data ? data.error : null;
  return typeof code === 'string' && KNOWN_ERRORS.has(code)
    ? (code as VoiceErrorCode)
    : 'UNKNOWN';
};

const voicePath = (conversationId: string, action = '') =>
  `/api/v1/chat/conversations/${conversationId}/voice${action ? `/${action}` : ''}`;

export const STATES_PAGE_SIZE = 40;

export const fetchVoiceStates = async (conversationIds: string[]) => {
  const response = await api().get<VoiceState[]>('/api/v1/chat/voice_states', {
    params: { conversation_ids: conversationIds },
  });
  return response.data;
};

export const requestVoiceCredentials = async (conversationId: string) => {
  const response = await api().post<VoiceCredentials>(
    voicePath(conversationId, 'join'),
  );
  return response.data;
};

export const reportVoiceStatus = async (
  conversationId: string,
  status: { session_id: string; mic_muted: boolean; deafened: boolean },
) => {
  const response = await api().post<{ accepted: boolean }>(
    voicePath(conversationId, 'status'),
    status,
  );
  return response.data.accepted;
};

export const moderateVoiceParticipant = async (
  conversationId: string,
  action: 'kick' | 'mute',
  accountId: string,
) => {
  const response = await api().post<{ accepted: boolean }>(
    voicePath(conversationId, action),
    { account_id: accountId },
  );
  return response.data.accepted;
};
