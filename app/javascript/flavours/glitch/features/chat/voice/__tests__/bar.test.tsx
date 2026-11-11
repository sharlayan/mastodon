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
}));

vi.mock('flavours/glitch/api', () => ({ default: () => api }));
vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  store: { dispatch },
  useAppDispatch: () => dispatch,
  useAppSelector: () => false,
}));
vi.mock('../call', async (importOriginal) => ({
  ...(await importOriginal<typeof Call>()),
  ...engine,
}));

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
    engine.connectVoiceCall.mockClear();
    api.post.mockReset();
  });

  afterEach(() => {
    cleanup();
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
