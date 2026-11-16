import { IntlProvider } from 'react-intl';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from '@testing-library/react';

import type * as InitialState from 'flavours/glitch/initial_state';

import type { VoiceState } from '../api';
import type * as Call from '../call';
import { VoiceCallHeaderButton, VoiceCallPanel } from '../panel';
import type { VoiceRoom } from '../panel';
import { resetVoiceStatesForTests } from '../states';

await vi.hoisted(() => import('../../testing/match_media'));

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
const dispatch = vi.hoisted(() => vi.fn());
const engine = vi.hoisted(() => ({
  connectVoiceCall: vi.fn(() => Promise.resolve()),
  prepareVoiceCall: vi.fn(() => Promise.resolve()),
  toggleScreenShareWatch: vi.fn(),
  unwatchScreenShare: vi.fn(),
}));
const fakeCall = vi.hoisted(() => {
  let snapshot: Call.VoiceCallSnapshot | null = null;
  const listeners = new Set<() => void>();
  return {
    get: () => snapshot,
    set: (value: Call.VoiceCallSnapshot | null) => {
      snapshot = value;
      listeners.forEach((listener) => {
        listener();
      });
    },
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
});

vi.mock('flavours/glitch/api', () => ({ default: () => api }));
vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<typeof InitialState>()),
  me: 'me',
}));
vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  store: { dispatch },
  useAppDispatch: () => dispatch,
  useAppSelector: () => false,
}));
vi.mock('../call', async (importOriginal) => {
  const actual = await importOriginal<typeof Call>();
  const { useSyncExternalStore } = await import('react');
  return {
    ...actual,
    ...engine,
    useVoiceCall: () => {
      const real = actual.useVoiceCall();
      return useSyncExternalStore(fakeCall.subscribe, fakeCall.get) ?? real;
    },
  };
});

const bob = {
  id: 'bob',
  acct: 'bob',
  display_name: 'Bob',
  avatar: '/bob.png',
  avatar_static: '/bob.png',
};
const carol = {
  id: 'carol',
  acct: 'carol@remote.example',
  display_name: 'Carol',
  avatar: '/carol.png',
  avatar_static: '/carol.png',
};
const room: VoiceRoom = {
  id: 'room',
  title: 'Hikers',
  owned: true,
  accounts: [
    { id: 'me', acct: 'me', display_name: 'Me', avatar: '', avatar_static: '' },
    bob,
  ],
};
const voiceState = (extra: Partial<VoiceState> = {}): VoiceState => ({
  conversation_id: 'room',
  available: true,
  active: true,
  unavailable: false,
  max_participants: 10,
  updated_at: 1,
  participants: [
    {
      identity: 'https://example.com/users/bob',
      account_id: 'bob',
      account: bob,
      screen_sharing: false,
      mic_muted: true,
      deafened: false,
    },
    {
      identity: 'https://remote.example/users/carol',
      account_id: 'carol',
      account: carol,
      screen_sharing: false,
      mic_muted: null,
      deafened: null,
    },
  ],
  ...extra,
});
const credentials = {
  url: 'wss://example.com/voice-signal',
  token: 'lk-token',
  identity: 'https://example.com/users/me',
  media_provider: 'https://voice.example.org',
  ice_servers: null,
  screen_share_limits: null,
  allow_screen_share: true,
  max_participants: 10,
};

const selfIdentity = 'https://example.com/users/me';
const bobIdentity = 'https://example.com/users/bob';
const inCall = (
  extra: Partial<Call.VoiceCallSnapshot> = {},
): Call.VoiceCallSnapshot => ({
  status: 'connected',
  conversation: { id: 'room', title: 'Hikers' },
  identity: selfIdentity,
  mediaProvider: 'https://voice.example.org',
  allowScreenShare: true,
  micEnabled: true,
  deafened: false,
  audioBlocked: false,
  speakingIdentities: [],
  screenSharing: false,
  screenShareIdentities: [],
  watchingIdentities: [],
  ...extra,
});

const mount = () =>
  render(
    <IntlProvider locale='en'>
      <VoiceCallHeaderButton room={room} enabled />
      <VoiceCallPanel room={room} enabled />
    </IntlProvider>,
  );

const settle = () =>
  act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
  });

interface ConfirmAction {
  payload: { modalType: string; modalProps: { onConfirm: () => void } };
}

describe('voice call panel', () => {
  beforeEach(() => {
    resetVoiceStatesForTests();
    window.localStorage.clear();
    dispatch.mockReset();
    fakeCall.set(null);
    engine.connectVoiceCall.mockClear();
    engine.toggleScreenShareWatch.mockClear();
    engine.unwatchScreenShare.mockReset();
    api.post.mockReset().mockResolvedValue({ data: credentials });
  });

  afterEach(() => {
    cleanup();
  });

  it('shows who is in the call and asks once before using an outside media server', async () => {
    api.get.mockResolvedValue({ data: [voiceState()] });
    mount();
    await settle();

    expect(screen.getByText('2 people in call')).toBeTruthy();
    expect(screen.getAllByLabelText('Microphone muted')).toHaveLength(1);
    expect(screen.queryByLabelText('Sound turned off')).toBeNull();

    const [micChoice, ...moreMicChoices] = screen.getAllByRole('button', {
      name: 'Join with microphone off',
    });
    expect(moreMicChoices).toHaveLength(0);
    expect(micChoice?.getAttribute('aria-pressed')).toBe('false');
    fireEvent.click(micChoice as HTMLElement);
    expect(micChoice?.getAttribute('aria-pressed')).toBe('true');

    const [headerJoin, bannerJoin] = screen.getAllByRole('button', {
      name: 'Join call',
    });
    expect(headerJoin).toBeTruthy();
    if (!bannerJoin) throw new Error('Missing join button');
    fireEvent.click(bannerJoin);
    await settle();

    expect(api.post).toHaveBeenCalledWith(
      '/api/v1/chat/conversations/room/voice/join',
    );
    const action = dispatch.mock.calls[0]?.[0] as ConfirmAction;
    expect(action.payload.modalType).toBe('CONFIRM');
    expect(engine.connectVoiceCall).not.toHaveBeenCalled();

    act(() => {
      action.payload.modalProps.onConfirm();
    });
    expect(engine.connectVoiceCall).toHaveBeenCalledWith(
      { id: 'room', title: 'Hikers' },
      credentials,
      { micEnabled: false },
    );

    dispatch.mockReset();
    fireEvent.click(bannerJoin);
    await settle();
    expect(dispatch).not.toHaveBeenCalled();
    expect(engine.connectVoiceCall).toHaveBeenCalledTimes(2);
  });

  it('shows that the join request is in flight on both join buttons', async () => {
    api.get.mockResolvedValue({ data: [voiceState()] });
    let answer: (value: unknown) => void = () => undefined;
    api.post.mockReturnValueOnce(
      new Promise((resolve) => {
        answer = resolve;
      }),
    );
    mount();
    await settle();

    const [, bannerJoin] = screen.getAllByRole('button', { name: 'Join call' });
    fireEvent.click(bannerJoin as HTMLElement);
    await settle();
    expect(screen.queryAllByRole('button', { name: 'Join call' })).toHaveLength(
      0,
    );
    const header = screen.getByRole('button', { name: 'Connecting…' });
    expect(header.hasAttribute('disabled')).toBe(true);
    expect(bannerJoin?.textContent).toContain('Connecting…');
    expect(bannerJoin?.getAttribute('aria-disabled')).toBe('true');

    answer({ data: credentials });
    await settle();
    expect(screen.getAllByRole('button', { name: 'Join call' })).toHaveLength(
      2,
    );
  });

  it('shows an unavailable call button without offering microphone controls or joining', async () => {
    api.get.mockResolvedValue({
      data: [voiceState({ active: false, participants: [], available: false })],
    });
    const view = mount();
    expect(
      screen
        .getByRole('button', {
          name: 'The call status cannot be checked right now.',
        })
        .hasAttribute('disabled'),
    ).toBe(true);
    await settle();

    const button = screen.getByRole('button', {
      name: 'Voice calls are not available in this chat.',
    });
    expect(button.hasAttribute('disabled')).toBe(true);
    fireEvent.click(button);
    expect(api.post).not.toHaveBeenCalled();
    expect(
      screen.queryByRole('button', { name: 'Join with microphone off' }),
    ).toBeNull();
    expect(screen.queryByText(/in call/)).toBeNull();

    view.rerender(
      <IntlProvider locale='en'>
        <VoiceCallHeaderButton room={room} enabled={false} />
        <VoiceCallPanel room={room} enabled={false} />
      </IntlProvider>,
    );
    expect(screen.queryByRole('button', { name: /call/i })).toBeNull();
  });

  it('offers a fresh call from the header when nobody is in it', async () => {
    api.get.mockResolvedValue({
      data: [voiceState({ active: false, participants: [] })],
    });
    mount();
    await settle();

    expect(screen.getByRole('button', { name: 'Start a call' })).toBeTruthy();
    expect(
      screen.getByRole('button', { name: 'Join with microphone off' }),
    ).toBeTruthy();
  });

  it('keeps the microphone and sound buttons usable while connecting', async () => {
    api.get.mockResolvedValue({ data: [voiceState()] });
    fakeCall.set(inCall({ status: 'connecting' }));
    mount();
    await settle();

    expect(screen.getByText('Connecting…')).toBeTruthy();
    for (const name of ['Mute microphone', 'Turn off sound'])
      expect(
        screen.getByRole('button', { name }).hasAttribute('disabled'),
      ).toBe(false);
  });

  it('asks the owner before removing someone from the call', async () => {
    api.get.mockResolvedValue({ data: [voiceState()] });
    mount();
    await settle();

    fireEvent.click(screen.getByRole('button', { name: 'Options for Bob' }));
    fireEvent.click(screen.getByRole('button', { name: 'Remove from call' }));
    expect(api.post).not.toHaveBeenCalled();

    const action = dispatch.mock.calls[0]?.[0] as ConfirmAction & {
      payload: { modalProps: { title: string } };
    };
    expect(action.payload.modalProps.title).toBe('Remove Bob from the call?');
    act(() => {
      action.payload.modalProps.onConfirm();
    });
    expect(api.post).toHaveBeenCalledWith(
      '/api/v1/chat/conversations/room/voice/kick',
      { account_id: 'bob' },
    );
  });

  it('shows the call server and lets you watch your own screen share, in full screen also on iOS and in picture in picture only when enabled', async () => {
    api.get.mockResolvedValue({ data: [voiceState()] });
    Object.defineProperty(document, 'pictureInPictureEnabled', {
      configurable: true,
      value: false,
    });
    onTestFinished(() => {
      Reflect.deleteProperty(document, 'pictureInPictureEnabled');
    });
    fakeCall.set(inCall({ screenSharing: true }));
    const view = mount();
    await settle();

    expect(screen.getByText('Call server: voice.example.org')).toBeTruthy();

    const previews = screen.getAllByRole('button', { name: 'Watch screen' });
    expect(previews).toHaveLength(1);
    fireEvent.click(previews[0] as HTMLElement);
    expect(engine.toggleScreenShareWatch).toHaveBeenCalledWith(selfIdentity);

    act(() => {
      fakeCall.set(
        inCall({ screenSharing: true, watchingIdentities: [selfIdentity] }),
      );
    });
    const stage = view.container.querySelector('.chat-voice__stage');
    expect(stage?.querySelectorAll('video')).toHaveLength(1);
    const video = stage?.querySelector('video');
    expect(video?.muted).toBe(true);

    expect(
      screen.queryByRole('button', { name: 'Picture in picture' }),
    ).toBeNull();

    const webkitEnterFullscreen = vi.fn();
    Object.assign(video ?? {}, { webkitEnterFullscreen });
    fireEvent.click(screen.getByRole('button', { name: 'Full screen' }));
    expect(webkitEnterFullscreen).toHaveBeenCalled();
  });

  it('enlarges one of several watched screens without recreating the others', async () => {
    api.get.mockResolvedValue({ data: [voiceState()] });
    fakeCall.set(
      inCall({
        screenSharing: true,
        screenShareIdentities: [bobIdentity],
        watchingIdentities: [bobIdentity],
      }),
    );
    const view = mount();
    await settle();
    expect(screen.queryByRole('button', { name: 'Enlarge screen' })).toBeNull();

    act(() => {
      fakeCall.set(
        inCall({
          screenSharing: true,
          screenShareIdentities: [bobIdentity],
          watchingIdentities: [bobIdentity, selfIdentity],
        }),
      );
    });
    const stage = view.container.querySelector('.chat-voice__stage');
    const videos = [...(stage?.querySelectorAll('video') ?? [])];
    const [, enlargeSelf] = screen.getAllByRole('button', {
      name: 'Enlarge screen',
    });
    fireEvent.click(enlargeSelf as HTMLElement);

    expect(stage?.classList).toContain('chat-voice__stage--focus');
    const screens = stage?.querySelectorAll('.chat-voice__screen');
    expect(screens?.[1]?.className).toContain('chat-voice__screen--focused');
    expect(screens?.[0]?.className).toContain('chat-voice__screen--compact');
    expect(screen.getAllByRole('button', { name: 'Full screen' })).toHaveLength(
      1,
    );
    expect([...(stage?.querySelectorAll('video') ?? [])]).toEqual(videos);

    act(() => {
      fakeCall.set(
        inCall({
          screenSharing: true,
          screenShareIdentities: [bobIdentity],
          watchingIdentities: [bobIdentity],
        }),
      );
    });
    act(() => {
      fakeCall.set(
        inCall({
          screenSharing: true,
          screenShareIdentities: [bobIdentity],
          watchingIdentities: [bobIdentity, selfIdentity],
        }),
      );
    });
    expect(stage?.classList).not.toContain('chat-voice__stage--focus');
  });

  it('moves the focus to the next screen or back to the sharer after closing a screen', async () => {
    api.get.mockResolvedValue({ data: [voiceState()] });
    const watchingBoth = inCall({
      screenSharing: true,
      watchingIdentities: [bobIdentity, selfIdentity],
    });
    fakeCall.set(watchingBoth);
    engine.unwatchScreenShare.mockImplementation((identity: string) => {
      fakeCall.set({
        ...watchingBoth,
        watchingIdentities: watchingBoth.watchingIdentities.filter(
          (item) => item !== identity,
        ),
      });
    });
    const view = mount();
    await settle();
    const closeButtons = () => [
      ...view.container.querySelectorAll<HTMLButtonElement>(
        '.chat-voice__stage button[title="Stop watching"]',
      ),
    ];

    fireEvent.click(closeButtons()[0] as HTMLElement);
    expect(document.activeElement?.getAttribute('title')).toBe('Full screen');
    expect(document.activeElement?.closest('.chat-voice__screen')).toBeTruthy();

    act(() => {
      fakeCall.set(watchingBoth);
    });
    fireEvent.click(closeButtons()[1] as HTMLElement);
    expect(
      document.activeElement?.getAttribute('data-voice-watch-toggle'),
    ).toBe(selfIdentity);
  });

  it('closes the participant options when moving to another room', async () => {
    api.get.mockResolvedValue({
      data: [voiceState(), voiceState({ conversation_id: 'other' })],
    });
    const view = mount();
    await settle();
    fireEvent.click(screen.getByRole('button', { name: 'Options for Bob' }));
    expect(
      screen.getByRole('button', { name: 'Mute for everyone' }),
    ).toBeTruthy();

    view.rerender(
      <IntlProvider locale='en'>
        <VoiceCallHeaderButton room={{ ...room, id: 'other' }} enabled />
        <VoiceCallPanel room={{ ...room, id: 'other' }} enabled />
      </IntlProvider>,
    );
    await settle();
    expect(
      screen.queryByRole('button', { name: 'Mute for everyone' }),
    ).toBeNull();
  });
});
