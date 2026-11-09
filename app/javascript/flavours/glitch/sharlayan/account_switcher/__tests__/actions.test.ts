import { configureStore } from '@reduxjs/toolkit';

import { refreshAccountSwitches } from '../actions';
import { apiGetAccountSwitches } from '../api';
import type { ApiAccountSwitchesResponseJSON } from '../api_types';
import { accountSwitchesReducer } from '../reducer';

vi.mock('../api', () => ({ apiGetAccountSwitches: vi.fn() }));
vi.mock('flavours/glitch/actions/importer', () => ({
  importFetchedAccounts: vi.fn(() => ({ type: 'TEST_IMPORT_ACCOUNTS' })),
}));

const response = (pushForward: boolean): ApiAccountSwitchesResponseJSON => ({
  root_account_id: '1',
  parent: null,
  children: [
    {
      id: 'auth-2',
      created_at: '2026-11-07T00:00:00.000Z',
      target_account: {
        id: '2',
      } as ApiAccountSwitchesResponseJSON['children'][number]['target_account'],
      push_forward: pushForward,
      session_authorized: true,
      session_approval_pending: false,
    },
  ],
  inbound: [],
});

const deferred = <T>() => {
  let settle: (value: T) => void = () => undefined;
  const promise = new Promise<T>((resolve) => {
    settle = resolve;
  });
  return {
    promise,
    resolve: (value: T) => {
      settle(value);
    },
  };
};

const storedPush = () =>
  (
    JSON.parse(localStorage.getItem('linked_notif_prefs_1') ?? '{}') as Record<
      string,
      { push?: boolean }
    >
  )['2']?.push;

beforeEach(() => {
  localStorage.clear();
  vi.mocked(apiGetAccountSwitches).mockReset();
});

test('a response superseded by a newer request does not overwrite stored push preferences', async () => {
  const store = configureStore({
    reducer: { accountSwitches: accountSwitchesReducer },
  });
  const older = deferred<ApiAccountSwitchesResponseJSON>();
  const newer = deferred<ApiAccountSwitchesResponseJSON>();
  vi.mocked(apiGetAccountSwitches)
    .mockReturnValueOnce(older.promise)
    .mockReturnValueOnce(newer.promise);

  const first = store.dispatch(refreshAccountSwitches() as never);
  const second = store.dispatch(refreshAccountSwitches() as never);

  newer.resolve(response(true));
  await second;
  older.resolve(response(false));
  await first;

  expect(storedPush()).toBe(true);
});
