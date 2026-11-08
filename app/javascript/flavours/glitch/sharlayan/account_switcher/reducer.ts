import type { Reducer } from '@reduxjs/toolkit';
import {
  Map as ImmutableMap,
  Record as ImmutableRecord,
  List as ImmutableList,
} from 'immutable';

import {
  fetchAccountSwitches,
  refreshAccountSwitches,
  deleteAccountSwitch,
  deleteInboundAccountSwitch,
  setLinkedUnreadCounts,
  incrementLinkedUnreadCount,
} from './actions';
import type { ApiAccountSwitchesResponseJSON } from './api_types';

const AuthorizationRecord = ImmutableRecord({
  id: '',
  target_account_id: '',
  created_at: '',
  session_authorized: false,
  session_approval_pending: false,
});

type Authorization = ReturnType<typeof AuthorizationRecord>;

const initialState = ImmutableMap({
  items: ImmutableList<Authorization>(),
  inboundItems: ImmutableList<Authorization>(),
  parentAccountId: null as string | null,
  rootAccountId: null as string | null,
  isLoading: false,
  loaded: false,
  latestRequestId: null as string | null,
  linkedUnreadCounts: ImmutableMap<string, number>(),
});

type State = typeof initialState;

const clearPendingRequest = (state: State) =>
  state.set('isLoading', false).set('latestRequestId', null);

const applyAccountSwitches = (
  state: State,
  data: ApiAccountSwitchesResponseJSON,
) => {
  const items = ImmutableList(
    data.children.map((auth) =>
      AuthorizationRecord({
        id: auth.id,
        target_account_id: auth.target_account.id,
        created_at: auth.created_at,
        session_authorized: auth.session_authorized,
        session_approval_pending: auth.session_approval_pending,
      }),
    ),
  );
  const inboundItems = ImmutableList(
    data.inbound.map((auth) =>
      AuthorizationRecord({
        id: auth.id,
        target_account_id: auth.account.id,
        created_at: auth.created_at,
      }),
    ),
  );
  const authorizedIds = new Set(
    data.children
      .filter((auth) => auth.session_authorized)
      .map((auth) => auth.target_account.id),
  );

  return state
    .set('items', items)
    .set('inboundItems', inboundItems)
    .set('parentAccountId', data.parent?.id ?? null)
    .set('rootAccountId', data.root_account_id)
    .set('loaded', true)
    .update('linkedUnreadCounts', (counts) =>
      (counts as ImmutableMap<string, number>).filter((_count, accountId) =>
        authorizedIds.has(accountId),
      ),
    );
};

export const accountSwitchesReducer: Reducer<State> = (
  state = initialState,
  action,
) => {
  if (
    fetchAccountSwitches.pending.match(action) ||
    refreshAccountSwitches.pending.match(action)
  ) {
    return state
      .set('isLoading', true)
      .set('latestRequestId', action.meta.requestId);
  } else if (
    fetchAccountSwitches.fulfilled.match(action) ||
    refreshAccountSwitches.fulfilled.match(action)
  ) {
    if (state.get('latestRequestId') !== action.meta.requestId) return state;

    const settled = state.set('isLoading', false).set('latestRequestId', null);
    return action.payload
      ? applyAccountSwitches(settled, action.payload)
      : settled;
  } else if (
    fetchAccountSwitches.rejected.match(action) ||
    refreshAccountSwitches.rejected.match(action)
  ) {
    if (state.get('latestRequestId') !== action.meta.requestId) return state;

    return state.set('isLoading', false).set('latestRequestId', null);
  } else if (deleteAccountSwitch.fulfilled.match(action)) {
    const deletedId = action.payload;
    return clearPendingRequest(state).update('items', (items) =>
      (items as ImmutableList<Authorization>).filter(
        (item) => item.get('id') !== deletedId,
      ),
    );
  } else if (deleteInboundAccountSwitch.fulfilled.match(action)) {
    const deletedId = action.payload;
    return clearPendingRequest(state).update('inboundItems', (items) =>
      (items as ImmutableList<Authorization>).filter(
        (item) => item.get('id') !== deletedId,
      ),
    );
  } else if (setLinkedUnreadCounts.match(action)) {
    const counts = action.payload;
    let map = ImmutableMap<string, number>();
    for (const [accountId, count] of Object.entries(counts)) {
      map = map.set(accountId, count);
    }
    return state.set('linkedUnreadCounts', map);
  } else if (incrementLinkedUnreadCount.match(action)) {
    return state.update('linkedUnreadCounts', (counts) => {
      const unreadCounts = counts as ImmutableMap<string, number>;
      return unreadCounts.set(
        action.payload,
        Math.min((unreadCounts.get(action.payload) ?? 0) + 1, 100),
      );
    });
  }

  return state;
};
