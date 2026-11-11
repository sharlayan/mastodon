import { useEffect, useSyncExternalStore } from 'react';

import {
  CHAT_STREAM_POLLED,
  CHAT_STREAM_RECONNECTED,
  subscribeChatStream,
} from '../stream';

import { fetchVoiceStates, STATES_PAGE_SIZE } from './api';
import type { VoiceState } from './api';

export const VOICE_STATE_EVENT = 'chat.voice_state';

const EMPTY = new Map<string, VoiceState>();
const RETRY_MIN_MS = 5_000;
const RETRY_MAX_MS = 120_000;

let states: ReadonlyMap<string, VoiceState> = EMPTY;
const listeners = new Set<() => void>();
const watchers = new Map<string, number>();
const fetched = new Set<string>();
let flushScheduled = false;
let retryTimer: ReturnType<typeof setTimeout> | null = null;
let retryDelay = RETRY_MIN_MS;

const notify = () => {
  listeners.forEach((listener) => {
    listener();
  });
};

const isVoiceState = (value: unknown): value is VoiceState =>
  value !== null &&
  typeof value === 'object' &&
  typeof (value as VoiceState).conversation_id === 'string' &&
  typeof (value as VoiceState).updated_at === 'number' &&
  Array.isArray((value as VoiceState).participants);

export const applyVoiceState = (state: unknown) => {
  if (!isVoiceState(state)) return false;
  const known = states.get(state.conversation_id);
  if (known && known.updated_at > state.updated_at) return false;
  const next = new Map(states);
  next.set(state.conversation_id, state);
  states = next;
  notify();
  return true;
};

export const forgetVoiceState = (conversationId: string) => {
  fetched.delete(conversationId);
  if (!states.has(conversationId)) return;
  const next = new Map(states);
  next.delete(conversationId);
  states = next;
  notify();
};

const loadVoiceStates = async (ids: string[]) => {
  for (let index = 0; index < ids.length; index += STATES_PAGE_SIZE) {
    const page = ids.slice(index, index + STATES_PAGE_SIZE);
    try {
      const received = await fetchVoiceStates(page);
      received.forEach((state) => applyVoiceState(state));
      retryDelay = RETRY_MIN_MS;
    } catch {
      page.forEach((id) => fetched.delete(id));
      scheduleRetry();
    }
  }
};

const scheduleRetry = () => {
  if (retryTimer != null) return;
  retryTimer = setTimeout(() => {
    retryTimer = null;
    scheduleFlush();
  }, retryDelay);
  retryDelay = Math.min(retryDelay * 2, RETRY_MAX_MS);
};

const flush = () => {
  flushScheduled = false;
  const missing = [...watchers.keys()].filter((id) => !fetched.has(id));
  if (missing.length === 0) return;
  missing.forEach((id) => fetched.add(id));
  void loadVoiceStates(missing);
};

const scheduleFlush = () => {
  if (flushScheduled) return;
  flushScheduled = true;
  queueMicrotask(flush);
};

export const watchVoiceStates = (ids: readonly string[]) => {
  ids.forEach((id) => watchers.set(id, (watchers.get(id) ?? 0) + 1));
  scheduleFlush();
  return () => {
    ids.forEach((id) => {
      const count = (watchers.get(id) ?? 1) - 1;
      if (count > 0) watchers.set(id, count);
      else watchers.delete(id);
    });
  };
};

export const refreshVoiceStates = () => {
  fetched.clear();
  scheduleFlush();
};

export const voiceStatesSnapshot = () => states;

export const subscribeVoiceStates = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

subscribeChatStream(({ event, payload }) => {
  if (event === VOICE_STATE_EVENT) applyVoiceState(payload);
  else if (event === CHAT_STREAM_RECONNECTED || event === CHAT_STREAM_POLLED)
    refreshVoiceStates();
});

export const useVoiceStates = (ids: readonly string[], enabled = true) => {
  const key = enabled ? [...new Set(ids)].sort().join(',') : '';
  useEffect(() => {
    if (!key) return undefined;
    return watchVoiceStates(key.split(','));
  }, [key]);
  return useSyncExternalStore(subscribeVoiceStates, voiceStatesSnapshot);
};

export const useVoiceState = (id: string | undefined, enabled = true) =>
  useVoiceStates(id ? [id] : [], enabled).get(id ?? '');

export const resetVoiceStatesForTests = () => {
  if (retryTimer != null) clearTimeout(retryTimer);
  retryTimer = null;
  retryDelay = RETRY_MIN_MS;
  states = EMPTY;
  watchers.clear();
  fetched.clear();
  flushScheduled = false;
  notify();
};
