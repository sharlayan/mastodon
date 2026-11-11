import type { FC } from 'react';

import { useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link, useLocation } from 'react-router-dom';

import CallEndIcon from '@/material-icons/400-24px/call_end.svg?react';
import { IconButton } from 'flavours/glitch/components/icon_button';

import { useVoiceCall } from './call';
import { voiceMessages } from './messages';
import { statusMessage, useVoicePanelShown, VoiceCallControls } from './panel';
import { cancelPendingVoiceCall, usePendingVoiceCall } from './start';

const roomPath = (id: string) => `/chat/${id}`;

export const VoiceCallBar: FC = () => {
  const intl = useIntl();
  const call = useVoiceCall();
  const location = useLocation();
  const panelShown = useVoicePanelShown(call.conversation?.id);
  const pending = usePendingVoiceCall();
  const path = location.pathname.replace(/^\/deck(?=\/)/, '');

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
        <span className='chat-voice-bar__status' role='status'>
          {intl.formatMessage(statusMessage(call))}
        </span>
      </Link>
      <VoiceCallControls call={call} compact />
    </aside>
  );
};
