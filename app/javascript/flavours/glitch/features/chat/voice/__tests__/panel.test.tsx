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
import { VoiceCallHeaderButton, VoiceCallPanel } from '../panel';
import type { VoiceRoom } from '../panel';
import { resetVoiceStatesForTests } from '../states';

await vi.hoisted(() => import('../../testing/match_media'));

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
const dispatch = vi.hoisted(() => vi.fn());
const engine = vi.hoisted(() => ({
  connectVoiceCall: vi.fn(() => Promise.resolve()),
  prepareVoiceCall: vi.fn(() => Promise.resolve()),
}));

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
vi.mock('../call', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  ...engine,
}));

const bob = {
  id: 'bob',
  acct: 'bob',
  display_name: 'Bob',
  avatar: '/bob.png',
  avatar_static: '/bob.png',
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
    engine.connectVoiceCall.mockClear();
    api.post.mockReset().mockResolvedValue({ data: credentials });
  });

  afterEach(() => {
    cleanup();
  });

  it('shows who is in the call and asks once before using an outside media server', async () => {
    api.get.mockResolvedValue({ data: [voiceState()] });
    mount();
    await settle();

    expect(screen.getByText('1 person in call')).toBeTruthy();
    expect(screen.getByLabelText('Microphone muted')).toBeTruthy();

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
      { micEnabled: undefined },
    );

    dispatch.mockReset();
    fireEvent.click(bannerJoin);
    await settle();
    expect(dispatch).not.toHaveBeenCalled();
    expect(engine.connectVoiceCall).toHaveBeenCalledTimes(2);
  });

  it('hides the call controls when the room has no call or cannot have one', async () => {
    api.get.mockResolvedValue({
      data: [voiceState({ active: false, participants: [], available: false })],
    });
    mount();
    await settle();

    expect(screen.queryByRole('button', { name: /call/i })).toBeNull();
    expect(screen.queryByText(/in call/)).toBeNull();
  });

  it('offers a fresh call from the header when nobody is in it', async () => {
    api.get.mockResolvedValue({
      data: [voiceState({ active: false, participants: [] })],
    });
    mount();
    await settle();

    expect(screen.getByRole('button', { name: 'Start a call' })).toBeTruthy();
  });
});
