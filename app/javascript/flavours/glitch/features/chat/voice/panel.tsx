import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from 'react';
import type { ChangeEvent, FC } from 'react';

import { useIntl } from 'react-intl';

import classNames from 'classnames';

import CallIcon from '@/material-icons/400-24px/call.svg?react';
import CallEndIcon from '@/material-icons/400-24px/call_end.svg?react';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import FullscreenIcon from '@/material-icons/400-24px/fullscreen.svg?react';
import HeadphonesIcon from '@/material-icons/400-24px/headphones.svg?react';
import HeadsetOffIcon from '@/material-icons/400-24px/headset_off.svg?react';
import MicIcon from '@/material-icons/400-24px/mic.svg?react';
import MicOffIcon from '@/material-icons/400-24px/mic_off.svg?react';
import MoreHorizIcon from '@/material-icons/400-24px/more_horiz.svg?react';
import PersonRemoveIcon from '@/material-icons/400-24px/person_remove.svg?react';
import PictureInPictureIcon from '@/material-icons/400-24px/picture_in_picture_alt.svg?react';
import ScreenShareIcon from '@/material-icons/400-24px/screen_share.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings.svg?react';
import StopScreenShareIcon from '@/material-icons/400-24px/stop_screen_share.svg?react';
import VolumeUpIcon from '@/material-icons/400-24px/volume_up.svg?react';
import { showAlert } from 'flavours/glitch/actions/alerts';
import { Button } from 'flavours/glitch/components/button';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { me } from 'flavours/glitch/initial_state';
import { useAppDispatch } from 'flavours/glitch/store';

import type { ChatAccount } from '../account';
import { ChatAvatar, ChatDisplayName } from '../account';

import { moderateVoiceParticipant, voiceErrorCode } from './api';
import type { VoiceParticipant, VoiceState } from './api';
import {
  activeAudioDeviceId,
  attachScreenShare,
  canShareScreen,
  leaveVoiceCall,
  listAudioDevices,
  restartMicrophone,
  resumeAudio,
  selectAudioDevice,
  setDeafened,
  setMicEnabled,
  setParticipantVolume,
  startScreenShare,
  stopScreenShare,
  toggleScreenShareWatch,
  unwatchScreenShare,
  useVoiceCall,
  voiceErrorMessage,
} from './call';
import type { VoiceCallSnapshot } from './call';
import { voiceMessages } from './messages';
import {
  participantVolume,
  updateVoicePreferences,
  useVoicePreferences,
} from './preferences';
import type { ScreenShareQuality } from './preferences';
import { useStartVoiceCall } from './start';
import { useVoiceState } from './states';

export interface VoiceRoom {
  id: string;
  title: string;
  owned: boolean;
  accounts: ChatAccount[];
}

interface CallMember {
  identity: string;
  account: ChatAccount;
  self: boolean;
  micMuted: boolean;
  deafened: boolean;
  screenSharing: boolean;
  speaking: boolean;
}

const inThisCall = (call: VoiceCallSnapshot, roomId: string) =>
  call.status !== 'idle' && call.conversation?.id === roomId;

const membersOf = (
  state: VoiceState | undefined,
  call: VoiceCallSnapshot,
  room: VoiceRoom,
): CallMember[] => {
  const joined = inThisCall(call, room.id);
  const seen = new Set<string>();
  const members: CallMember[] = [];
  const fromServer = (participant: VoiceParticipant) => {
    if (seen.has(participant.identity)) return;
    seen.add(participant.identity);
    const self = joined && participant.identity === call.identity;
    members.push({
      identity: participant.identity,
      account: participant.account,
      self,
      micMuted: self ? !call.micEnabled : participant.mic_muted,
      deafened: self ? call.deafened : participant.deafened,
      screenSharing: self ? call.screenSharing : participant.screen_sharing,
      speaking:
        joined && call.speakingIdentities.includes(participant.identity),
    });
  };
  state?.participants.forEach(fromServer);
  const selfAccount = room.accounts.find((account) => account.id === me);
  if (joined && call.identity && !seen.has(call.identity) && selfAccount) {
    members.unshift({
      identity: call.identity,
      account: selfAccount,
      self: true,
      micMuted: !call.micEnabled,
      deafened: call.deafened,
      screenSharing: call.screenSharing,
      speaking: call.speakingIdentities.includes(call.identity),
    });
  }
  if (joined)
    call.screenShareIdentities.forEach((identity) => {
      const member = members.find((item) => item.identity === identity);
      if (member) member.screenSharing = true;
    });
  return members;
};

export const VoiceCallBadge: FC<{ state: VoiceState | undefined }> = ({
  state,
}) => {
  const intl = useIntl();
  const count = state?.participants.length ?? 0;
  if (!state?.active || count === 0) return null;
  const label = intl.formatMessage(voiceMessages.inCall, { count });
  return (
    <span
      className='chat-voice__badge'
      title={label}
      role='img'
      aria-label={label}
    >
      <Icon id='headphones' icon={HeadphonesIcon} />
      {count}
    </span>
  );
};

export const VoiceCallHeaderButton: FC<{
  room: VoiceRoom;
  enabled: boolean;
}> = ({ room, enabled }) => {
  const intl = useIntl();
  const state = useVoiceState(room.id, enabled);
  const call = useVoiceCall();
  const start = useStartVoiceCall();
  const handleClick = useCallback(() => {
    start({ id: room.id, title: room.title });
  }, [room.id, room.title, start]);

  if (!enabled || !state?.available || inThisCall(call, room.id)) return null;
  const label = intl.formatMessage(
    state.active ? voiceMessages.join : voiceMessages.startCall,
  );
  return (
    <button
      type='button'
      className='column-header__button'
      title={label}
      aria-label={label}
      onClick={handleClick}
    >
      <Icon id='call' icon={CallIcon} />
    </button>
  );
};

const ScreenVideo: FC<{
  identity: string;
  preview?: boolean;
  className?: string;
  videoRef?: (element: HTMLVideoElement | null) => void;
}> = ({ identity, preview = false, className, videoRef }) => {
  const element = useRef<HTMLVideoElement | null>(null);
  useEffect(() => {
    const video = element.current;
    if (!video) return undefined;
    return attachScreenShare(identity, video, { preview });
  }, [identity, preview]);
  const setRef = useCallback(
    (video: HTMLVideoElement | null) => {
      element.current = video;
      videoRef?.(video);
    },
    [videoRef],
  );
  return (
    <video
      ref={setRef}
      className={className}
      autoPlay
      playsInline
      muted
      disablePictureInPicture={preview}
    />
  );
};

const ScreenStage: FC<{ identity: string; member: CallMember | undefined }> = ({
  identity,
  member,
}) => {
  const intl = useIntl();
  const video = useRef<HTMLVideoElement | null>(null);
  const frame = useRef<HTMLDivElement | null>(null);
  const setVideo = useCallback((element: HTMLVideoElement | null) => {
    video.current = element;
  }, []);
  const handleFullscreen = useCallback(() => {
    void frame.current?.requestFullscreen().catch(() => undefined);
  }, []);
  const handlePictureInPicture = useCallback(() => {
    const element = video.current;
    if (!element || !('requestPictureInPicture' in element)) return;
    void element.requestPictureInPicture().catch(() => undefined);
  }, []);
  const handleClose = useCallback(() => {
    unwatchScreenShare(identity);
  }, [identity]);
  const pictureInPicture =
    typeof document !== 'undefined' && 'pictureInPictureEnabled' in document;

  return (
    <div className='chat-voice__screen' ref={frame}>
      <ScreenVideo identity={identity} videoRef={setVideo} />
      <div className='chat-voice__screen-bar'>
        <span className='chat-voice__screen-name'>
          {member && <ChatDisplayName account={member.account} />}
        </span>
        {pictureInPicture && (
          <IconButton
            icon='picture-in-picture'
            iconComponent={PictureInPictureIcon}
            title={intl.formatMessage(voiceMessages.pictureInPicture)}
            onClick={handlePictureInPicture}
          />
        )}
        <IconButton
          icon='fullscreen'
          iconComponent={FullscreenIcon}
          title={intl.formatMessage(voiceMessages.fullscreen)}
          onClick={handleFullscreen}
        />
        <IconButton
          icon='close'
          iconComponent={CloseIcon}
          title={intl.formatMessage(voiceMessages.stopWatching)}
          onClick={handleClose}
        />
      </div>
    </div>
  );
};

const MemberTile: FC<{
  member: CallMember;
  watching: boolean;
  selected: boolean;
  canWatch: boolean;
  menu: boolean;
  onSelect: (identity: string) => void;
}> = ({ member, watching, selected, canWatch, menu, onSelect }) => {
  const intl = useIntl();
  const handleWatch = useCallback(() => {
    toggleScreenShareWatch(member.identity);
  }, [member.identity]);
  const handleSelect = useCallback(() => {
    onSelect(member.identity);
  }, [member.identity, onSelect]);
  const name = member.account.display_name || member.account.acct;

  return (
    <li
      className={classNames('chat-voice__member', {
        'chat-voice__member--speaking': member.speaking,
        'chat-voice__member--selected': selected,
      })}
    >
      {member.screenSharing && canWatch ? (
        <button
          type='button'
          className={classNames('chat-voice__preview', {
            'chat-voice__preview--watching': watching,
          })}
          title={intl.formatMessage(
            watching ? voiceMessages.stopWatching : voiceMessages.watch,
          )}
          aria-pressed={watching}
          onClick={handleWatch}
        >
          <ScreenVideo identity={member.identity} preview />
          <Icon id='screen-share' icon={ScreenShareIcon} />
        </button>
      ) : (
        <span className='chat-voice__avatar'>
          <ChatAvatar account={member.account} size={40} />
        </span>
      )}
      <span className='chat-voice__member-name'>
        {member.self ? (
          intl.formatMessage(voiceMessages.you)
        ) : (
          <ChatDisplayName account={member.account} />
        )}
      </span>
      <span className='chat-voice__member-flags'>
        {member.micMuted && (
          <Icon
            id='mic-off'
            icon={MicOffIcon}
            aria-label={intl.formatMessage(voiceMessages.micMuted)}
          />
        )}
        {member.deafened && (
          <Icon
            id='headset-off'
            icon={HeadsetOffIcon}
            aria-label={intl.formatMessage(voiceMessages.deafened)}
          />
        )}
        {member.screenSharing && (
          <Icon
            id='screen-share'
            icon={ScreenShareIcon}
            aria-label={intl.formatMessage(voiceMessages.sharingScreen)}
          />
        )}
      </span>
      {menu && !member.self && (
        <IconButton
          className='chat-voice__member-menu'
          icon='ellipsis-h'
          iconComponent={MoreHorizIcon}
          title={intl.formatMessage(voiceMessages.participantMenu, { name })}
          active={selected}
          expanded={selected}
          onClick={handleSelect}
        />
      )}
    </li>
  );
};

const VolumeSlider: FC<{
  identity: string;
  audio: 'voice' | 'screenShare';
  label: string;
}> = ({ identity, audio, label }) => {
  useVoicePreferences();
  const volume = participantVolume(identity, audio);
  const handleChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      setParticipantVolume(identity, audio, Number(event.target.value) / 100);
    },
    [audio, identity],
  );
  return (
    <label className='chat-voice__volume'>
      <Icon id='volume-up' icon={VolumeUpIcon} />
      <span>{label}</span>
      <input
        type='range'
        min={0}
        max={100}
        step={5}
        value={Math.round(volume * 100)}
        onChange={handleChange}
        aria-valuetext={`${Math.round(volume * 100)}%`}
      />
    </label>
  );
};

const MemberOptions: FC<{
  room: VoiceRoom;
  member: CallMember;
  joined: boolean;
  onClose: () => void;
}> = ({ room, member, joined, onClose }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const moderate = useCallback(
    (action: 'kick' | 'mute') => {
      moderateVoiceParticipant(room.id, action, member.account.id).catch(
        (error: unknown) => {
          dispatch(
            showAlert({ message: voiceErrorMessage(voiceErrorCode(error)) }),
          );
        },
      );
      if (action === 'kick') onClose();
    },
    [dispatch, member.account.id, onClose, room.id],
  );
  const handleMute = useCallback(() => {
    moderate('mute');
  }, [moderate]);
  const handleKick = useCallback(() => {
    moderate('kick');
  }, [moderate]);

  return (
    <div className='chat-voice__options'>
      <div className='chat-voice__options-head'>
        <ChatDisplayName account={member.account} withHandle />
        <IconButton
          icon='close'
          iconComponent={CloseIcon}
          title={intl.formatMessage(voiceMessages.close)}
          onClick={onClose}
        />
      </div>
      {joined && (
        <VolumeSlider
          identity={member.identity}
          audio='voice'
          label={intl.formatMessage(voiceMessages.voiceVolume)}
        />
      )}
      {joined && member.screenSharing && (
        <VolumeSlider
          identity={member.identity}
          audio='screenShare'
          label={intl.formatMessage(voiceMessages.screenVolume)}
        />
      )}
      {room.owned && (
        <div className='chat-voice__options-actions'>
          <Button compact secondary onClick={handleMute}>
            <Icon id='mic-off' icon={MicOffIcon} />
            {intl.formatMessage(voiceMessages.forceMute)}
          </Button>
          <Button compact dangerous onClick={handleKick}>
            <Icon id='person-remove' icon={PersonRemoveIcon} />
            {intl.formatMessage(voiceMessages.removeFromCall)}
          </Button>
        </div>
      )}
    </div>
  );
};

const DeviceSelect: FC<{
  kind: 'audioinput' | 'audiooutput';
  label: string;
}> = ({ kind, label }) => {
  const intl = useIntl();
  useVoicePreferences();
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([]);
  useEffect(() => {
    let active = true;
    const load = () => {
      listAudioDevices(kind)
        .then((list) => {
          if (active) setDevices(list);
        })
        .catch(() => undefined);
    };
    load();
    const mediaDevices = navigator.mediaDevices as MediaDevices | undefined;
    mediaDevices?.addEventListener('devicechange', load);
    return () => {
      active = false;
      mediaDevices?.removeEventListener('devicechange', load);
    };
  }, [kind]);
  const handleChange = useCallback(
    (event: ChangeEvent<HTMLSelectElement>) => {
      void selectAudioDevice(kind, event.target.value).catch(() => undefined);
    },
    [kind],
  );
  if (kind === 'audiooutput' && !('setSinkId' in HTMLMediaElement.prototype))
    return null;
  const selected = activeAudioDeviceId(kind);
  return (
    <label className='chat-voice__setting'>
      <span>{label}</span>
      <select value={selected} onChange={handleChange}>
        {!devices.some((device) => device.deviceId === 'default') && (
          <option value='default'>
            {intl.formatMessage(voiceMessages.systemDefault)}
          </option>
        )}
        {devices.map((device) => (
          <option key={device.deviceId} value={device.deviceId}>
            {device.label || device.deviceId}
          </option>
        ))}
      </select>
    </label>
  );
};

const QUALITY_LABELS = {
  sharp: voiceMessages.qualitySharp,
  smooth: voiceMessages.qualitySmooth,
  high: voiceMessages.qualityHigh,
} as const;

type ProcessingKey =
  | 'echoCancellation'
  | 'noiseSuppression'
  | 'autoGainControl';

const ProcessingToggle: FC<{ name: ProcessingKey; label: string }> = ({
  name,
  label,
}) => {
  const preferences = useVoicePreferences();
  const handleChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      updateVoicePreferences({ [name]: event.target.checked });
      void restartMicrophone().catch(() => undefined);
    },
    [name],
  );
  return (
    <label className='chat-voice__toggle'>
      <input
        type='checkbox'
        checked={preferences[name]}
        onChange={handleChange}
      />
      <span>{label}</span>
    </label>
  );
};

const VoiceSettings: FC<{ screenShare: boolean }> = ({ screenShare }) => {
  const intl = useIntl();
  const preferences = useVoicePreferences();
  const handleQuality = useCallback((event: ChangeEvent<HTMLSelectElement>) => {
    updateVoicePreferences({
      screenShareQuality: event.target.value as ScreenShareQuality,
    });
  }, []);
  const handleScreenAudio = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      updateVoicePreferences({ screenShareAudio: event.target.checked });
    },
    [],
  );

  return (
    <div className='chat-voice__settings'>
      <DeviceSelect
        kind='audioinput'
        label={intl.formatMessage(voiceMessages.inputDevice)}
      />
      <DeviceSelect
        kind='audiooutput'
        label={intl.formatMessage(voiceMessages.outputDevice)}
      />
      <ProcessingToggle
        name='echoCancellation'
        label={intl.formatMessage(voiceMessages.echoCancellation)}
      />
      <ProcessingToggle
        name='noiseSuppression'
        label={intl.formatMessage(voiceMessages.noiseSuppression)}
      />
      <ProcessingToggle
        name='autoGainControl'
        label={intl.formatMessage(voiceMessages.autoGainControl)}
      />
      {screenShare && (
        <>
          <label className='chat-voice__setting'>
            <span>{intl.formatMessage(voiceMessages.screenShareQuality)}</span>
            <select
              value={preferences.screenShareQuality}
              onChange={handleQuality}
            >
              {(Object.keys(QUALITY_LABELS) as ScreenShareQuality[]).map(
                (quality) => (
                  <option key={quality} value={quality}>
                    {intl.formatMessage(QUALITY_LABELS[quality])}
                  </option>
                ),
              )}
            </select>
          </label>
          <label className='chat-voice__toggle'>
            <input
              type='checkbox'
              checked={preferences.screenShareAudio}
              onChange={handleScreenAudio}
            />
            <span>{intl.formatMessage(voiceMessages.screenShareAudio)}</span>
          </label>
        </>
      )}
    </div>
  );
};

export const VoiceCallControls: FC<{
  call: VoiceCallSnapshot;
  compact?: boolean;
  settingsOpen?: boolean;
  onToggleSettings?: () => void;
}> = ({ call, compact = false, settingsOpen = false, onToggleSettings }) => {
  const intl = useIntl();
  const handleMic = useCallback(() => {
    void setMicEnabled(!call.micEnabled);
  }, [call.micEnabled]);
  const handleDeafen = useCallback(() => {
    setDeafened(!call.deafened);
  }, [call.deafened]);
  const handleScreen = useCallback(() => {
    void (call.screenSharing ? stopScreenShare() : startScreenShare());
  }, [call.screenSharing]);
  const handleLeave = useCallback(() => {
    void leaveVoiceCall();
  }, []);
  const busy = call.status === 'connecting';
  const screenShare = call.allowScreenShare && canShareScreen();

  return (
    <div className='chat-voice__controls'>
      <IconButton
        icon={call.micEnabled ? 'mic' : 'mic-off'}
        iconComponent={call.micEnabled ? MicIcon : MicOffIcon}
        title={intl.formatMessage(
          call.micEnabled ? voiceMessages.muteMic : voiceMessages.unmuteMic,
        )}
        active={!call.micEnabled}
        disabled={busy}
        onClick={handleMic}
      />
      <IconButton
        icon={call.deafened ? 'headset-off' : 'headphones'}
        iconComponent={call.deafened ? HeadsetOffIcon : HeadphonesIcon}
        title={intl.formatMessage(
          call.deafened ? voiceMessages.undeafen : voiceMessages.deafen,
        )}
        active={call.deafened}
        disabled={busy}
        onClick={handleDeafen}
      />
      {!compact && screenShare && (
        <IconButton
          icon={call.screenSharing ? 'stop-screen-share' : 'screen-share'}
          iconComponent={
            call.screenSharing ? StopScreenShareIcon : ScreenShareIcon
          }
          title={intl.formatMessage(
            call.screenSharing
              ? voiceMessages.stopSharing
              : voiceMessages.shareScreen,
          )}
          active={call.screenSharing}
          disabled={busy}
          onClick={handleScreen}
        />
      )}
      {!compact && onToggleSettings && (
        <IconButton
          icon='settings'
          iconComponent={SettingsIcon}
          title={intl.formatMessage(voiceMessages.settings)}
          active={settingsOpen}
          expanded={settingsOpen}
          onClick={onToggleSettings}
        />
      )}
      <IconButton
        className='chat-voice__leave'
        icon='call-end'
        iconComponent={CallEndIcon}
        title={intl.formatMessage(voiceMessages.leave)}
        onClick={handleLeave}
      />
    </div>
  );
};

export const statusMessage = (call: VoiceCallSnapshot) =>
  call.status === 'connecting'
    ? voiceMessages.connecting
    : call.status === 'reconnecting'
      ? voiceMessages.reconnecting
      : voiceMessages.connected;

const shownPanels = new Map<string, number>();
const panelListeners = new Set<() => void>();

const notifyPanels = () => {
  panelListeners.forEach((listener) => {
    listener();
  });
};

const subscribePanels = (listener: () => void) => {
  panelListeners.add(listener);
  return () => {
    panelListeners.delete(listener);
  };
};

const usePanelPresence = (conversationId: string | null) => {
  useEffect(() => {
    if (conversationId == null) return undefined;
    shownPanels.set(conversationId, (shownPanels.get(conversationId) ?? 0) + 1);
    notifyPanels();
    return () => {
      const count = (shownPanels.get(conversationId) ?? 1) - 1;
      if (count > 0) shownPanels.set(conversationId, count);
      else shownPanels.delete(conversationId);
      notifyPanels();
    };
  }, [conversationId]);
};

export const useVoicePanelShown = (conversationId: string | undefined) =>
  useSyncExternalStore(
    subscribePanels,
    () => conversationId != null && shownPanels.has(conversationId),
  );

export const VoiceCallPanel: FC<{ room: VoiceRoom; enabled: boolean }> = ({
  room,
  enabled,
}) => {
  const intl = useIntl();
  const state = useVoiceState(room.id, enabled);
  const call = useVoiceCall();
  const start = useStartVoiceCall();
  const [selected, setSelected] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const joined = inThisCall(call, room.id);
  const members = useMemo(
    () => membersOf(state, call, room),
    [state, call, room],
  );

  const handleJoin = useCallback(() => {
    start({ id: room.id, title: room.title });
  }, [room.id, room.title, start]);
  const handleSelect = useCallback((identity: string) => {
    setSelected((current) => (current === identity ? null : identity));
  }, []);
  const handleCloseOptions = useCallback(() => {
    setSelected(null);
  }, []);
  const handleToggleSettings = useCallback(() => {
    setSettingsOpen((open) => !open);
  }, []);
  const handleResumeAudio = useCallback(() => {
    void resumeAudio().catch(() => undefined);
  }, []);
  usePanelPresence(enabled && joined ? room.id : null);

  if (!enabled) return null;
  if (!joined && !(state?.active && members.length > 0)) return null;

  const selectedMember = members.find((member) => member.identity === selected);
  const watching = joined ? call.watchingIdentities : [];

  return (
    <section
      className={classNames('chat-voice', { 'chat-voice--joined': joined })}
      aria-label={intl.formatMessage(voiceMessages.inCall, {
        count: members.length,
      })}
    >
      {joined && watching.length > 0 && (
        <div className='chat-voice__stage'>
          {watching.map((identity) => (
            <ScreenStage
              key={identity}
              identity={identity}
              member={members.find((member) => member.identity === identity)}
            />
          ))}
        </div>
      )}

      <div className='chat-voice__summary'>
        <span className='chat-voice__status' role='status'>
          {joined
            ? intl.formatMessage(statusMessage(call))
            : intl.formatMessage(voiceMessages.inCall, {
                count: members.length,
              })}
          {state?.unavailable && (
            <span className='chat-voice__warning'>
              {intl.formatMessage(voiceMessages.callUnavailableNow)}
            </span>
          )}
        </span>
        {!joined && state?.available && (
          <Button compact onClick={handleJoin}>
            <Icon id='call' icon={CallIcon} />
            {intl.formatMessage(voiceMessages.join)}
          </Button>
        )}
      </div>

      <ul className='chat-voice__members'>
        {members.map((member) => (
          <MemberTile
            key={member.identity}
            member={member}
            canWatch={joined && !member.self}
            menu={joined || room.owned}
            watching={watching.includes(member.identity)}
            selected={selected === member.identity}
            onSelect={handleSelect}
          />
        ))}
      </ul>

      {selectedMember && !selectedMember.self && (joined || room.owned) && (
        <MemberOptions
          room={room}
          member={selectedMember}
          joined={joined}
          onClose={handleCloseOptions}
        />
      )}

      {joined && call.audioBlocked && (
        <Button block secondary onClick={handleResumeAudio}>
          {intl.formatMessage(voiceMessages.enableAudio)}
        </Button>
      )}

      {joined && (
        <VoiceCallControls
          call={call}
          settingsOpen={settingsOpen}
          onToggleSettings={handleToggleSettings}
        />
      )}

      {joined && settingsOpen && (
        <VoiceSettings
          screenShare={call.allowScreenShare && canShareScreen()}
        />
      )}
    </section>
  );
};
