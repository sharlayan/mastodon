import { useCallback, useState } from 'react';
import type { FC } from 'react';

import { useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link, useLocation } from 'react-router-dom';

import CallEndIcon from '@/material-icons/400-24px/call_end.svg?react';
import MicIcon from '@/material-icons/400-24px/mic.svg?react';
import MicOffIcon from '@/material-icons/400-24px/mic_off.svg?react';
import RadioButtonCheckedIcon from '@/material-icons/400-24px/radio_button_checked.svg?react';
import VolumeUpIcon from '@/material-icons/400-24px/volume_up.svg?react';
import { Button } from 'flavours/glitch-classic/components/button';
import { Icon } from 'flavours/glitch-classic/components/icon';
import { IconButton } from 'flavours/glitch-classic/components/icon_button';

import { canShareScreen, resumeAudio, useVoiceCall } from './call';
import { voiceMessages } from './messages';
import {
  statusMessage,
  useVoicePanelShown,
  VoiceCallControls,
  VoiceSettings,
} from './panel';
import { cancelPendingVoiceCall, usePendingVoiceCall } from './start';
import { useVoiceState } from './states';

const roomPath = (id: string) => `/chat/${id}`;

export const VoiceCallBar: FC = () => {
  const intl = useIntl();
  const call = useVoiceCall();
  const location = useLocation();
  const panelShown = useVoicePanelShown(call.conversation?.id);
  const pending = usePendingVoiceCall();
  const path = location.pathname.replace(/^\/deck(?=\/)/, '');
  const [settingsFor, setSettingsFor] = useState<string | null>(null);
  const conversationId = call.conversation?.id ?? null;
  const settingsOpen = conversationId != null && settingsFor === conversationId;
  const voiceState = useVoiceState(
    conversationId ?? undefined,
    conversationId != null,
  );
  const recording =
    voiceState?.participants.some(
      (participant) => participant.recording === true,
    ) ?? false;
  const handleToggleSettings = useCallback(() => {
    setSettingsFor((open) => (open === conversationId ? null : conversationId));
  }, [conversationId]);
  const handleResumeAudio = useCallback(() => {
    void resumeAudio().catch(() => undefined);
  }, []);

  if (pending && path !== roomPath(pending.id))
    return (
      <aside
        className='chat-voice-bar chat-voice-bar--pending'
        aria-label={intl.formatMessage(voiceMessages.connected)}
      >
        <Link
          className='chat-voice-bar__room'
          to={roomPath(pending.id)}
          title={intl.formatMessage(voiceMessages.backToRoom)}
        >
          <span className='chat-voice-bar__title'>{pending.title}</span>
          <span className='chat-voice-bar__status' role='status'>
            {intl.formatMessage(voiceMessages.connecting)}
          </span>
        </Link>
        <div className='chat-voice__controls'>
          <IconButton
            className='chat-voice__leave'
            icon='call-end'
            iconComponent={CallEndIcon}
            title={intl.formatMessage(voiceMessages.leave)}
            onClick={cancelPendingVoiceCall}
          />
        </div>
      </aside>
    );

  if (call.status === 'idle' || !call.conversation || panelShown) return null;
  if (path === roomPath(call.conversation.id)) return null;

  const speaking =
    call.status === 'connected' &&
    call.micEnabled &&
    call.identity != null &&
    call.speakingIdentities.includes(call.identity);
  const micLabel = intl.formatMessage(
    speaking
      ? voiceMessages.micSpeaking
      : call.micEnabled
        ? voiceMessages.micOn
        : voiceMessages.micMuted,
  );

  return (
    <aside
      className={classNames('chat-voice-bar', {
        'chat-voice-bar--pending': call.status !== 'connected',
      })}
      aria-label={intl.formatMessage(voiceMessages.connected)}
    >
      <Link
        className='chat-voice-bar__room'
        to={roomPath(call.conversation.id)}
        title={intl.formatMessage(voiceMessages.backToRoom)}
      >
        <span className='chat-voice-bar__title'>{call.conversation.title}</span>
        <span className='chat-voice-bar__line'>
          <Icon
            id={call.micEnabled ? 'mic' : 'mic-off'}
            icon={call.micEnabled ? MicIcon : MicOffIcon}
            className={classNames('chat-voice-bar__mic', {
              'chat-voice-bar__mic--speaking': speaking,
              'chat-voice-bar__mic--muted': !call.micEnabled,
            })}
            aria-label={micLabel}
          />
          <span className='chat-voice-bar__status' role='status'>
            {intl.formatMessage(statusMessage(call))}
          </span>
          {recording && (
            <span className='chat-voice-bar__recording' role='status'>
              <Icon id='radio-button-checked' icon={RadioButtonCheckedIcon} />
              {intl.formatMessage(voiceMessages.recording)}
            </span>
          )}
        </span>
      </Link>
      {call.audioBlocked && (
        <Button
          compact
          className='chat-voice-bar__audio'
          title={intl.formatMessage(voiceMessages.enableAudio)}
          onClick={handleResumeAudio}
        >
          <Icon id='volume-up' icon={VolumeUpIcon} />
          <span>{intl.formatMessage(voiceMessages.enableAudio)}</span>
        </Button>
      )}
      <VoiceCallControls
        call={call}
        settingsOpen={settingsOpen}
        onToggleSettings={handleToggleSettings}
      />
      {settingsOpen && (
        <div className='chat-voice-bar__settings'>
          <VoiceSettings
            screenShare={call.allowScreenShare && canShareScreen()}
          />
        </div>
      )}
    </aside>
  );
};
