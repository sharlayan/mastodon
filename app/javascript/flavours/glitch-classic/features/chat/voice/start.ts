import { useCallback, useSyncExternalStore } from 'react';

import { useIntl } from 'react-intl';

import { openModal } from 'flavours/glitch-classic/actions/modal';
import { useAppDispatch } from 'flavours/glitch-classic/store';

import { requestVoiceCredentials } from './api';
import type { VoiceCredentials } from './api';
import {
  connectVoiceCall,
  leaveVoiceCall,
  notifyVoiceCallFailure,
  prepareVoiceCall,
  voiceCallSnapshot,
  voiceLeaveRevision,
} from './call';
import type { VoiceCallConversation } from './call';
import { voiceMessages } from './messages';
import {
  acknowledgeMediaProvider,
  isMediaProviderAcknowledged,
} from './preferences';

const needsMediaNotice = (credentials: VoiceCredentials) => {
  const origin = credentials.media_provider;
  return (
    origin !== '' &&
    origin !== window.location.origin &&
    !isMediaProviderAcknowledged(origin)
  );
};

export const hostOf = (origin: string) => {
  try {
    return new URL(origin).host;
  } catch {
    return origin;
  }
};

interface PendingStart {
  conversation: VoiceCallConversation;
}

let pending: PendingStart | null = null;
const pendingListeners = new Set<() => void>();

const setPending = (value: PendingStart | null) => {
  pending = value;
  pendingListeners.forEach((listener) => {
    listener();
  });
};

const subscribePending = (listener: () => void) => {
  pendingListeners.add(listener);
  return () => {
    pendingListeners.delete(listener);
  };
};

const currentPending = () => pending;

const pendingConversation = () => currentPending()?.conversation ?? null;

export const usePendingVoiceCall = () =>
  useSyncExternalStore(subscribePending, pendingConversation);

export const cancelPendingVoiceCall = () => {
  setPending(null);
  void leaveVoiceCall();
};

export const useStartVoiceCall = () => {
  const dispatch = useAppDispatch();
  const intl = useIntl();

  const confirm = useCallback(
    (
      title: string,
      message: string,
      confirmLabel: string,
      onConfirm: () => void,
    ) => {
      dispatch(
        openModal({
          modalType: 'CONFIRM',
          modalProps: { title, message, confirm: confirmLabel, onConfirm },
        }),
      );
    },
    [dispatch],
  );

  const begin = useCallback(
    async (conversation: VoiceCallConversation, micEnabled?: boolean) => {
      if (pending) return;
      const entry = { conversation };
      setPending(entry);
      const revision = voiceLeaveRevision();
      let credentials: VoiceCredentials;
      try {
        [credentials] = await Promise.all([
          requestVoiceCredentials(conversation.id),
          prepareVoiceCall(),
        ]);
      } catch (error) {
        if (revision === voiceLeaveRevision()) notifyVoiceCallFailure(error);
        return;
      } finally {
        if (currentPending() === entry) setPending(null);
      }
      if (revision !== voiceLeaveRevision()) return;

      const connect = () => {
        void connectVoiceCall(conversation, credentials, { micEnabled });
      };

      const mediaNotice = needsMediaNotice(credentials);
      const recording = credentials.recording === true;
      if (!mediaNotice && !recording) {
        connect();
        return;
      }

      const notices = [
        ...(recording
          ? [intl.formatMessage(voiceMessages.recordingJoinNotice)]
          : []),
        ...(mediaNotice
          ? [
              intl.formatMessage(voiceMessages.mediaNotice, {
                host: hostOf(credentials.media_provider),
              }),
            ]
          : []),
      ];

      confirm(
        intl.formatMessage(
          recording
            ? voiceMessages.recordingJoinTitle
            : voiceMessages.mediaNoticeTitle,
        ),
        notices.join(' '),
        intl.formatMessage(
          recording ? voiceMessages.join : voiceMessages.mediaNoticeConfirm,
        ),
        () => {
          if (mediaNotice) acknowledgeMediaProvider(credentials.media_provider);
          connect();
        },
      );
    },
    [confirm, intl],
  );

  return useCallback(
    (conversation: VoiceCallConversation, micEnabled?: boolean) => {
      const call = voiceCallSnapshot();
      if (
        call.status !== 'idle' &&
        call.conversation &&
        call.conversation.id !== conversation.id
      ) {
        confirm(
          intl.formatMessage(voiceMessages.switchCallTitle),
          intl.formatMessage(voiceMessages.switchCall),
          intl.formatMessage(voiceMessages.switchCallConfirm),
          () => {
            void begin(conversation, micEnabled);
          },
        );
        return;
      }
      if (call.status !== 'idle') return;
      void begin(conversation, micEnabled);
    },
    [begin, confirm, intl],
  );
};
