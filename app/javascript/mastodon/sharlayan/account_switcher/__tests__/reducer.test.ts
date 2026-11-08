import { refreshAccountSwitches, setLinkedUnreadCounts } from '../actions';
import type { ApiAccountSwitchesResponseJSON } from '../api_types';
import { accountSwitchesReducer } from '../reducer';

const itemCount = (state: ReturnType<typeof accountSwitchesReducer>) =>
  (state.get('items') as unknown as { size: number }).size;

const child = (id: string, sessionAuthorized: boolean) => ({
  id: `auth-${id}`,
  created_at: '2026-11-07T00:00:00.000Z',
  target_account: {
    id,
  } as ApiAccountSwitchesResponseJSON['children'][number]['target_account'],
  push_forward: false,
  session_authorized: sessionAuthorized,
  session_approval_pending: false,
});

const response = (
  children: ApiAccountSwitchesResponseJSON['children'],
): ApiAccountSwitchesResponseJSON => ({
  root_account_id: '1',
  parent: null,
  children,
  inbound: [],
});

const pending = (requestId: string) =>
  refreshAccountSwitches.pending(requestId, undefined);
const fulfilled = (
  requestId: string,
  payload: ApiAccountSwitchesResponseJSON | null,
) => refreshAccountSwitches.fulfilled(payload, requestId, undefined);

describe('accountSwitchesReducer', () => {
  it('ignores a response that finishes after a newer request started', () => {
    let state = accountSwitchesReducer(undefined, pending('old'));
    state = accountSwitchesReducer(state, pending('new'));
    state = accountSwitchesReducer(
      state,
      fulfilled('new', response([child('2', true)])),
    );
    state = accountSwitchesReducer(
      state,
      fulfilled('old', response([child('2', true), child('3', true)])),
    );

    expect(itemCount(state)).toBe(1);
    expect(state.get('isLoading')).toBe(false);
  });

  it('keeps the previous list when a background refresh fails', () => {
    let state = accountSwitchesReducer(undefined, pending('first'));
    state = accountSwitchesReducer(
      state,
      fulfilled('first', response([child('2', true)])),
    );
    state = accountSwitchesReducer(state, pending('second'));
    state = accountSwitchesReducer(state, fulfilled('second', null));

    expect(itemCount(state)).toBe(1);
    expect(state.get('loaded')).toBe(true);
    expect(state.get('isLoading')).toBe(false);
  });

  it('drops unread counts of accounts that are no longer authorized', () => {
    let state = accountSwitchesReducer(
      undefined,
      setLinkedUnreadCounts({ '2': 4, '3': 1 }),
    );
    state = accountSwitchesReducer(state, pending('refresh'));
    state = accountSwitchesReducer(
      state,
      fulfilled('refresh', response([child('2', false), child('3', true)])),
    );

    const counts = state.get('linkedUnreadCounts') as unknown as Map<
      string,
      number
    >;
    expect(counts.get('2')).toBeUndefined();
    expect(counts.get('3')).toBe(1);
  });
});
