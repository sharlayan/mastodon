import { IntlProvider } from 'react-intl';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { apiGetAvatarDecorations } from '@/flavours/glitch/api/accounts';

import { DecorationModal } from '../decoration_modal';

const dispatch = vi.hoisted(() => vi.fn());

vi.mock('@/flavours/glitch/api/accounts', () => ({
  apiGetAvatarDecorations: vi.fn(),
}));
vi.mock('@/flavours/glitch/actions/alerts', () => ({
  showAlertForError: vi.fn((error: unknown) => ({ type: 'TEST_ALERT', error })),
}));
vi.mock('@/flavours/glitch/reducers/slices/profile_edit', () => ({
  patchProfile: vi.fn(),
}));
vi.mock('@/flavours/glitch/store', () => ({
  useAppDispatch: () => dispatch,
  useAppSelector: (
    selector: (state: {
      profileEdit: { profile: unknown; isPending: boolean };
    }) => unknown,
  ) =>
    selector({
      profileEdit: {
        profile: { avatar: '/avatar.png', avatarDecorations: [] },
        isPending: false,
      },
    }),
}));
vi.mock('@/flavours/glitch/components/loading_indicator', () => ({
  LoadingIndicator: () => <div data-testid='loading' />,
}));
vi.mock('../../ui/components/dialog_modal', () => ({
  DialogModal: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
}));

afterEach(cleanup);

describe('<DecorationModal />', () => {
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
