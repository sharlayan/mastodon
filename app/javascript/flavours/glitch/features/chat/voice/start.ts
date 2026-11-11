import { useCallback } from 'react';

import { useIntl } from 'react-intl';

import { openModal } from 'flavours/glitch/actions/modal';
import { useAppDispatch } from 'flavours/glitch/store';

import { requestVoiceCredentials } from './api';
import type { VoiceCredentials } from './api';
import {
  connectVoiceCall,
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

const hostOf = (origin: string) => {
  try {
    return new URL(origin).host;
  } catch {
    return origin;
  }
};

let starting = false;

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
      if (starting) return;
      starting = true;
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
        starting = false;
      }
      if (revision !== voiceLeaveRevision()) return;

      const connect = () => {
        void connectVoiceCall(conversation, credentials, { micEnabled });
      };

      if (!needsMediaNotice(credentials)) {
        connect();
        return;
      }

      confirm(
        intl.formatMessage(voiceMessages.mediaNoticeTitle),
        intl.formatMessage(voiceMessages.mediaNotice, {
          host: hostOf(credentials.media_provider),
        }),
        intl.formatMessage(voiceMessages.mediaNoticeConfirm),
        () => {
          acknowledgeMediaProvider(credentials.media_provider);
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
