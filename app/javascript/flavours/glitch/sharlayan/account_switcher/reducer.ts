import type { Reducer } from '@reduxjs/toolkit';
import {
  Map as ImmutableMap,
  Record as ImmutableRecord,
  List as ImmutableList,
} from 'immutable';

import {
  fetchAccountSwitches,
  deleteAccountSwitch,
  deleteInboundAccountSwitch,
  setLinkedUnreadCounts,
  incrementLinkedUnreadCount,
} from './actions';

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
  linkedUnreadCounts: ImmutableMap<string, number>(),
});

type State = typeof initialState;

export const accountSwitchesReducer: Reducer<State> = (
  state = initialState,
  action,
) => {
  if (fetchAccountSwitches.pending.match(action)) {
    return state.set('isLoading', true);
  } else if (fetchAccountSwitches.fulfilled.match(action)) {
    const data = action.payload;
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
    return state
      .set('items', items)
      .set('inboundItems', inboundItems)
      .set('parentAccountId', data.parent?.id ?? null)
      .set('rootAccountId', data.root_account_id)
      .set('isLoading', false)
      .set('loaded', true);
  } else if (fetchAccountSwitches.rejected.match(action)) {
    return state.set('isLoading', false);
  } else if (deleteAccountSwitch.fulfilled.match(action)) {
    const deletedId = action.payload;
    return state.update('items', (items) =>
      (items as ImmutableList<Authorization>).filter(
        (item) => item.get('id') !== deletedId,
      ),
    );
  } else if (deleteInboundAccountSwitch.fulfilled.match(action)) {
    const deletedId = action.payload;
    return state.update('inboundItems', (items) =>
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
