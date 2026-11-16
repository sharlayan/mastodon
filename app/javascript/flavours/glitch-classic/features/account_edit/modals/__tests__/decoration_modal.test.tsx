import { IntlProvider } from 'react-intl';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from '@testing-library/react';

import { apiGetAvatarDecorations } from '@/flavours/glitch-classic/api/accounts';
import { patchProfile } from '@/flavours/glitch-classic/reducers/slices/profile_edit';

import { DecorationModal } from '../decoration_modal';

const dispatch = vi.hoisted(() => vi.fn());

vi.mock('@/flavours/glitch-classic/api/accounts', () => ({
  apiGetAvatarDecorations: vi.fn(),
}));
vi.mock('@/flavours/glitch-classic/actions/alerts', () => ({
  showAlertForError: vi.fn((error: unknown) => ({ type: 'TEST_ALERT', error })),
}));
vi.mock('@/flavours/glitch-classic/reducers/slices/profile_edit', () => ({
  patchProfile: Object.assign(
    vi.fn((payload: unknown) => ({ type: 'PATCH_PROFILE', payload })),
    {
      fulfilled: {
        match: (action: { type?: string }) =>
          action.type === 'profileEdit/patchProfile/fulfilled',
      },
    },
  ),
}));
vi.mock('@/flavours/glitch-classic/store', () => ({
  useAppDispatch: () => dispatch,
  useAppSelector: (
    selector: (state: {
      profileEdit: { profile: unknown; isPending: boolean };
    }) => unknown,
  ) =>
    selector({
      profileEdit: {
        profile: {
          avatar: '/avatar.png',
          avatarDecorations: [
            {
              id: 'existing-decoration',
              angle: 0,
              flip_h: false,
              offset_x: 0,
              offset_y: 0,
              scale: 1,
              opacity: 1,
            },
          ],
        },
        isPending: false,
      },
    }),
}));
vi.mock('@/flavours/glitch-classic/components/loading_indicator', () => ({
  LoadingIndicator: () => <div data-testid='loading' />,
}));
vi.mock('../../ui/components/dialog_modal', () => ({
  DialogModal: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
}));

beforeEach(() => {
  dispatch.mockReset();
  vi.mocked(patchProfile).mockClear();
  vi.mocked(apiGetAvatarDecorations).mockResolvedValue([]);
});
afterEach(cleanup);

describe('<DecorationModal />', () => {
  it.each([
    ['validation failure', { response: { status: 422 } }],
    ['network failure', new Error('Network unavailable')],
  ])(
    'keeps edited decorations open after a %s and allows a successful retry',
    async (_label, error) => {
      const onClose = vi.fn();
      dispatch.mockResolvedValue({
        type: 'profileEdit/patchProfile/rejected',
        payload: { error },
      });

      render(
        <IntlProvider locale='en'>
          <DecorationModal onClose={onClose} />
        </IntlProvider>,
      );
      fireEvent.click(
        screen.getByRole('button', { name: 'existing-decoration' }),
      );
      fireEvent.click(screen.getByRole('button', { name: 'Remove' }));

      await act(async () => {
        fireEvent.click(screen.getByRole('button', { name: 'Save' }));
        await Promise.resolve();
      });

      expect(onClose).not.toHaveBeenCalled();
      expect(screen.getByText('No decorations added yet.')).toBeTruthy();
      expect(patchProfile).toHaveBeenLastCalledWith({ avatar_decorations: [] });

      dispatch.mockResolvedValue({
        type: 'profileEdit/patchProfile/fulfilled',
      });
      await act(async () => {
        fireEvent.click(screen.getByRole('button', { name: 'Save' }));
        await Promise.resolve();
      });

      expect(patchProfile).toHaveBeenCalledTimes(2);
      expect(patchProfile).toHaveBeenLastCalledWith({ avatar_decorations: [] });
      expect(onClose).toHaveBeenCalledTimes(1);
    },
  );

  it('stops loading and shows an alert when decorations cannot be loaded', async () => {
    const error = new Error('Request failed');
    vi.mocked(apiGetAvatarDecorations).mockRejectedValue(error);

    render(
      <IntlProvider locale='en'>
        <DecorationModal onClose={vi.fn()} />
      </IntlProvider>,
    );

    await vi.waitFor(() => {
      expect(dispatch).toHaveBeenCalledWith({ type: 'TEST_ALERT', error });
    });

    fireEvent.click(screen.getByRole('button', { name: 'Add decoration' }));

    expect(screen.queryByTestId('loading')).toBeNull();
    expect(
      screen.getByText('No profile decorations are available on this server.'),
    ).toBeTruthy();
  });
});
