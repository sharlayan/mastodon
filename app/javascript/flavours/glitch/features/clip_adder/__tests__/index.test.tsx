import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router-dom';

import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';

import { ClipAdder } from '..';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn((action: unknown) =>
    typeof action === 'function' ? Promise.resolve() : action,
  ),
  apiGetStatusClips: vi.fn(),
  apiAddStatusToClip: vi.fn(),
  apiRemoveStatusFromClip: vi.fn(),
}));

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: () => [{ id: 'c1', title: 'Clip one' }],
}));

vi.mock('flavours/glitch/api/clips', () => ({
  apiGetStatusClips: mocks.apiGetStatusClips,
  apiAddStatusToClip: mocks.apiAddStatusToClip,
  apiRemoveStatusFromClip: mocks.apiRemoveStatusFromClip,
}));

const alertDispatched = () =>
  mocks.dispatch.mock.calls.some(
    ([action]) =>
      typeof action === 'object' &&
      action !== null &&
      (action as { type?: string }).type === 'alerts/show',
  );

const renderAdder = (onClose = vi.fn()) => {
  render(
    <IntlProvider locale='en'>
      <MemoryRouter>
        <ClipAdder statusId='s1' onClose={onClose} />
      </MemoryRouter>
    </IntlProvider>,
  );

  return onClose;
};

describe('ClipAdder', () => {
  beforeEach(() => {
    mocks.dispatch.mockClear();
    mocks.apiGetStatusClips.mockReset();
    mocks.apiAddStatusToClip.mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  it('shows an error and closes instead of showing every clip as unchecked when membership cannot be loaded', async () => {
    mocks.apiGetStatusClips.mockRejectedValue(new Error('network'));
    const onClose = renderAdder();

    await waitFor(() => {
      expect(alertDispatched()).toBe(true);
    });
    expect(onClose).toHaveBeenCalled();
    expect(screen.queryByRole('checkbox')).toBeNull();
  });

  it('shows an error and restores the toggle when adding fails', async () => {
    mocks.apiGetStatusClips.mockResolvedValue([]);
    mocks.apiAddStatusToClip.mockRejectedValue(new Error('network'));
    renderAdder();

    const toggle = await screen.findByRole('checkbox');
    fireEvent.click(toggle);

    await waitFor(() => {
      expect(alertDispatched()).toBe(true);
    });
    await waitFor(() => {
      expect((toggle as HTMLInputElement).checked).toBe(false);
    });
  });
});
