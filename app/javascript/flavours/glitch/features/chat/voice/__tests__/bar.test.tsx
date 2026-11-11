import type { ReactNode } from 'react';

import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router-dom';

import {
  act,
  cleanup,
  fireEvent,
  render,
  renderHook,
  screen,
} from '@testing-library/react';

import { VoiceCallBar } from '../bar';
import type * as Call from '../call';
import { useStartVoiceCall } from '../start';

await vi.hoisted(() => import('../../testing/match_media'));

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
const dispatch = vi.hoisted(() => vi.fn());
const engine = vi.hoisted(() => ({
  connectVoiceCall: vi.fn(() => Promise.resolve()),
  prepareVoiceCall: vi.fn(() => Promise.resolve()),
  resumeAudio: vi.fn(() => Promise.resolve()),
  startScreenShare: vi.fn(() => Promise.resolve()),
  listAudioDevices: vi.fn(() => Promise.resolve([])),
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

const credentials = {
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

const mount = (path = '/home') =>
  render(
    <IntlProvider locale='en'>
      <MemoryRouter initialEntries={[path]}>
        <VoiceCallBar />
      </MemoryRouter>
    </IntlProvider>,
  );

const settle = () =>
  act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
  });

describe('voice call bar', () => {
  beforeEach(() => {
    dispatch.mockReset();
    fakeCall.set(null);
    engine.connectVoiceCall.mockClear();
    engine.resumeAudio.mockClear();
    engine.startScreenShare.mockClear();
    api.post.mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  it('offers the audio, screen share and settings controls and shows when your microphone picks up sound', () => {
    Object.defineProperty(window.navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getDisplayMedia: vi.fn(),
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
      },
    });
    onTestFinished(() => {
      Reflect.deleteProperty(window.navigator, 'mediaDevices');
    });
    const identity = 'https://example.com/users/me';
    const connected: Call.VoiceCallSnapshot = {
      status: 'connected',
      conversation: { id: 'room', title: 'Hikers' },
      identity,
      mediaProvider: null,
      allowScreenShare: true,
      micEnabled: true,
      deafened: false,
      audioBlocked: true,
      speakingIdentities: [identity],
      screenSharing: false,
      screenShareIdentities: [],
      watchingIdentities: [],
    };
    fakeCall.set(connected);
    mount();

    expect(
      screen.getByRole('img', { name: 'Microphone input detected' }),
    ).toBeTruthy();
    fireEvent.click(
      screen.getByRole('button', { name: 'Click to play call audio' }),
    );
    expect(engine.resumeAudio).toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Share screen' }));
    expect(engine.startScreenShare).toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Call settings' }));
    expect(screen.getByLabelText('Echo cancellation')).toBeTruthy();

    act(() => {
      fakeCall.set({ ...connected, micEnabled: false, audioBlocked: false });
    });
    expect(screen.getByRole('img', { name: 'Microphone muted' })).toBeTruthy();
    expect(
      screen.queryByRole('button', { name: 'Click to play call audio' }),
    ).toBeNull();
  });

  it('shows a call that is still being joined and lets you cancel it', async () => {
    let answer: (value: unknown) => void = () => undefined;
    api.post.mockReturnValueOnce(
      new Promise((resolve) => {
        answer = resolve;
      }),
    );
    mount();
    const { result } = renderHook(() => useStartVoiceCall(), { wrapper });

    act(() => {
      result.current({ id: 'room', title: 'Hikers' }, true);
    });
    await settle();
    expect(screen.getByText('Hikers')).toBeTruthy();
    expect(screen.getByRole('status').textContent).toBe('Connecting…');

    fireEvent.click(screen.getByRole('button', { name: 'Leave call' }));
    expect(screen.queryByText('Hikers')).toBeNull();
    answer({ data: credentials });
    await settle();
    expect(engine.connectVoiceCall).not.toHaveBeenCalled();
  });
});
