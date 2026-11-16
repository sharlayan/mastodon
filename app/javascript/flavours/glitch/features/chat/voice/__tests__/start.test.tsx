import type { ReactNode } from 'react';

import { IntlProvider } from 'react-intl';

import { cleanup, renderHook } from '@testing-library/react';

import type { VoiceCredentials } from '../api';
import { useStartVoiceCall } from '../start';

const dispatch = vi.hoisted(() => vi.fn());
const pending = vi.hoisted(() => ({
  resolve: vi.fn<(credentials: unknown) => void>(),
}));
const engine = vi.hoisted(() => ({
  revision: 0,
  connectVoiceCall: vi.fn(() => Promise.resolve()),
  prepareVoiceCall: vi.fn(() => Promise.resolve()),
  notifyVoiceCallFailure: vi.fn(),
}));
const requestVoiceCredentials = vi.hoisted(() =>
  vi.fn(
    () =>
      new Promise((resolve) => {
        pending.resolve.mockImplementation(resolve);
      }),
  ),
);

vi.mock('flavours/glitch/store', () => ({ useAppDispatch: () => dispatch }));
vi.mock('../api', () => ({ requestVoiceCredentials }));
vi.mock('../call', () => ({
  connectVoiceCall: engine.connectVoiceCall,
  prepareVoiceCall: engine.prepareVoiceCall,
  notifyVoiceCallFailure: engine.notifyVoiceCallFailure,
  voiceCallSnapshot: () => ({ status: 'idle', conversation: null }),
  voiceLeaveRevision: () => engine.revision,
}));

const credentials: VoiceCredentials = {
  url: 'wss://example.com/voice-signal',
  token: 'lk-token',
  identity: 'https://example.com/users/me',
  media_provider: '',
  ice_servers: null,
  screen_share_limits: null,
  allow_screen_share: true,
  max_participants: 10,
};

const wrapper = ({ children }: { children: ReactNode }) => (
  <IntlProvider locale='en'>{children}</IntlProvider>
);

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('starting a voice call', () => {
  beforeEach(() => {
    engine.revision = 0;
    engine.connectVoiceCall.mockClear();
    requestVoiceCredentials.mockClear();
  });

  afterEach(() => {
    cleanup();
  });

  it('asks for credentials once while another start is pending', async () => {
    const first = renderHook(() => useStartVoiceCall(), { wrapper });
    const second = renderHook(() => useStartVoiceCall(), { wrapper });

    first.result.current({ id: '5', title: 'Room' });
    second.result.current({ id: '5', title: 'Room' });
    await flush();
    pending.resolve(credentials);
    await flush();

    expect(requestVoiceCredentials).toHaveBeenCalledTimes(1);
    expect(engine.connectVoiceCall).toHaveBeenCalledTimes(1);
  });

  it('does not connect when the call was left while waiting for credentials', async () => {
    const { result } = renderHook(() => useStartVoiceCall(), { wrapper });

    result.current({ id: '5', title: 'Room' });
    await flush();
    engine.revision++;
    pending.resolve(credentials);
    await flush();

    expect(engine.connectVoiceCall).not.toHaveBeenCalled();
  });
});
