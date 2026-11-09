import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { createMemoryHistory } from 'history';

import CircleMembers from '../members';

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  apiGetCircleAccounts: vi.fn(),
  apiAddAccountToCircle: vi.fn(),
  apiRemoveAccountFromCircle: vi.fn(),
  showAlertForError: vi.fn((error: unknown) => ({ type: 'ALERT', error })),
}));

const state = {
  accounts: {
    get: (id: string) => ({
      id,
      acct: 'alice',
      fields: [],
      followers_count: 0,
    }),
  },
};

vi.mock('flavours/glitch/store', () => ({
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: (selector: (value: typeof state) => unknown) =>
    selector(state),
}));

vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  me: undefined,
}));

vi.mock('flavours/glitch/selectors/user_lists', () => ({
  selectUserListWithoutMe: () => undefined,
}));

vi.mock('flavours/glitch/actions/accounts', () => ({
  expandFollowers: vi.fn(),
  fetchFollowers: vi.fn(),
  fetchRelationships: vi.fn(),
}));

vi.mock('flavours/glitch/actions/alerts', () => ({
  showAlertForError: mocks.showAlertForError,
}));

vi.mock('flavours/glitch/actions/circles', () => ({ fetchCircle: vi.fn() }));

vi.mock('flavours/glitch/actions/importer', () => ({
  importFetchedAccounts: vi.fn(),
}));

vi.mock('flavours/glitch/api/circles', () => ({
  apiGetCircleAccounts: mocks.apiGetCircleAccounts,
  apiAddAccountToCircle: mocks.apiAddAccountToCircle,
  apiRemoveAccountFromCircle: mocks.apiRemoveAccountFromCircle,
}));

vi.mock('flavours/glitch/hooks/useSearchAccounts', () => ({
  useSearchAccounts: () => ({
    accounts: [],
    isLoading: false,
    searchAccounts: vi.fn(),
    resetAccounts: vi.fn(),
  }),
}));

vi.mock('flavours/glitch/components/scrollable_list', () => ({
  default: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
}));

vi.mock('flavours/glitch/components/avatar', () => ({ Avatar: () => null }));
vi.mock('flavours/glitch/components/badge', () => ({
  VerifiedBadge: () => null,
}));
vi.mock('flavours/glitch/components/display_name', () => ({
  DisplayName: () => null,
}));
vi.mock('flavours/glitch/components/short_number', () => ({
  ShortNumber: () => null,
}));
vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => null,
}));
vi.mock('flavours/glitch/components/column/search_header', () => ({
  ColumnSearchHeader: () => null,
}));
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const renderMembers = () => {
  const history = createMemoryHistory({
    initialEntries: ['/circles/7/members'],
  });

  render(
    <IntlProvider locale='en'>
      <Router history={history}>
        <Route path='/circles/:id/members'>
          <CircleMembers multiColumn />
        </Route>
      </Router>
    </IntlProvider>,
  );
};

describe('CircleMembers', () => {
  afterEach(() => {
    cleanup();
    vi.clearAllMocks();
  });

  it('keeps a member listed and alerts when removal fails', async () => {
    const error = new Error('500');
    let rejectRemoval: (reason: unknown) => void = () => undefined;
    mocks.apiGetCircleAccounts.mockResolvedValue([{ id: '1' }]);
    mocks.apiRemoveAccountFromCircle.mockReturnValue(
      new Promise((_resolve, reject) => {
        rejectRemoval = reject;
      }),
    );

    renderMembers();

    const remove = await screen.findByRole('button', { name: 'Remove' });
    fireEvent.click(remove);
    fireEvent.click(remove);

    expect(mocks.apiRemoveAccountFromCircle).toHaveBeenCalledTimes(1);
    expect(remove.hasAttribute('disabled')).toBe(true);

    rejectRemoval(error);

    await waitFor(() => {
      expect(mocks.showAlertForError).toHaveBeenCalledWith(error);
    });
    expect(screen.getByRole('button', { name: 'Remove' })).toBeTruthy();
  });

  it('removes a member only after the request succeeds', async () => {
    mocks.apiGetCircleAccounts.mockResolvedValue([{ id: '1' }]);
    mocks.apiRemoveAccountFromCircle.mockResolvedValue({});

    renderMembers();

    fireEvent.click(await screen.findByRole('button', { name: 'Remove' }));

    await waitFor(() => {
      expect(screen.queryByRole('button', { name: 'Remove' })).toBeNull();
    });
  });
});
