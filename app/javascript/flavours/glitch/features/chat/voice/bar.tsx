import type { FC } from 'react';

import { useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link, useLocation } from 'react-router-dom';

import { useVoiceCall } from './call';
import { voiceMessages } from './messages';
import { statusMessage, useVoicePanelShown, VoiceCallControls } from './panel';

const roomPath = (id: string) => `/chat/${id}`;

export const VoiceCallBar: FC = () => {
  const intl = useIntl();
  const call = useVoiceCall();
  const location = useLocation();
  const panelShown = useVoicePanelShown(call.conversation?.id);

  if (call.status === 'idle' || !call.conversation || panelShown) return null;
  const path = location.pathname.replace(/^\/deck(?=\/)/, '');
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
