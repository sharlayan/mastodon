import { IntlProvider } from 'react-intl';

import { List, Map as ImmutableMap } from 'immutable';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { AccountSwitcherModal } from '../modal';

const state = {
  accountSwitches: ImmutableMap<string, unknown>({
    items: List([
      {
        id: 'auth-2',
        target_account_id: '2',
        created_at: '2026-11-07T00:00:00.000Z',
        session_authorized: true,
        session_approval_pending: false,
      },
    ]),
    inboundItems: List(),
    parentAccountId: null,
    rootAccountId: '1',
    isLoading: false,
    loaded: true,
    linkedUnreadCounts: ImmutableMap<string, number>(),
  }),
  accounts: ImmutableMap({
    '2': ImmutableMap({ id: '2', username: 'linked', acct: 'linked' }),
    '3': ImmutableMap({ id: '3', username: 'parent', acct: 'parent' }),
  }),
};

let currentState = state;

vi.mock('flavours/glitch/initial_state', () => ({
  me: undefined,
  serverStoredAccountSwitchingEnabled: true,
}));
vi.mock('flavours/glitch/store', () => ({
  useAppSelector: (selector: (value: typeof state) => unknown) =>
    selector(currentState),
  useAppDispatch: () => () => ({
    unwrap: () => Promise.resolve(),
  }),
}));
vi.mock('flavours/glitch/components/avatar', () => ({
  Avatar: () => null,
}));
vi.mock('flavours/glitch/components/display_name', () => ({
  DisplayName: () => null,
}));
vi.mock('../actions', () => ({
  fetchAccountSwitches: vi.fn(),
  deleteAccountSwitch: vi.fn(),
  deleteInboundAccountSwitch: vi.fn(),
  enableLinkedPushForward: vi.fn(),
  disableLinkedPushForward: vi.fn(),
}));

const renderModal = () =>
  render(
    <IntlProvider locale='en'>
      <AccountSwitcherModal onClose={vi.fn()} />
    </IntlProvider>,
  );

afterEach(() => {
  cleanup();
  currentState = state;
  vi.restoreAllMocks();
});

describe('<AccountSwitcherModal />', () => {
  it('does not switch accounts when keys are pressed on buttons inside a linked account row', () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    renderModal();

    fireEvent.keyDown(screen.getByTitle('Notifications'), { key: 'Enter' });
    fireEvent.keyDown(screen.getByTitle('Notifications'), { key: ' ' });
    fireEvent.keyDown(screen.getByTitle('Remove account'), { key: 'Enter' });
    expect(confirm).not.toHaveBeenCalled();

    const row = screen.getByTitle('Switch to linked');
    const space = fireEvent.keyDown(row, { key: ' ' });
    expect(space).toBe(false);
    expect(confirm).toHaveBeenCalledTimes(1);
  });

  it('does not switch accounts when keys are pressed on buttons inside the parent account row', () => {
    currentState = {
      ...state,
      accountSwitches: state.accountSwitches
        .set('parentAccountId', '3')
        .set('items', List()),
    };
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    renderModal();

    fireEvent.keyDown(screen.getByTitle('Notifications'), { key: 'Enter' });
    expect(confirm).not.toHaveBeenCalled();

    const space = fireEvent.keyDown(screen.getByTitle('Back to parent'), {
      key: ' ',
    });
    expect(space).toBe(false);
    expect(confirm).toHaveBeenCalledTimes(1);
  });
});
