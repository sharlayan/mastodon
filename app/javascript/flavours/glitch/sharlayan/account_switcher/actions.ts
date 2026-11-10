import { createAction } from '@reduxjs/toolkit';

import { importFetchedAccounts } from 'flavours/glitch/actions/importer';
import { me } from 'flavours/glitch/initial_state';
import type { AppDispatch, RootState } from 'flavours/glitch/store';
import { createDataLoadingThunk } from 'flavours/glitch/store/typed_functions';

import {
  apiGetAccountSwitches,
  apiDeleteAccountSwitch,
  apiDeleteInboundAccountSwitch,
  apiCreatePushForward,
  apiDeletePushForward,
} from './api';
import type { ApiAccountSwitchesResponseJSON } from './api_types';

export const setLinkedUnreadCounts = createAction<Record<string, number>>(
  'accountSwitches/setLinkedUnreadCounts',
);
export const incrementLinkedUnreadCount = createAction<string>(
  'accountSwitches/incrementLinkedUnreadCount',
);

const importAccountSwitches = (
  data: ApiAccountSwitchesResponseJSON,
  dispatch: AppDispatch,
) => {
  const accounts = data.children.map((auth) => auth.target_account);
  accounts.push(...data.inbound.map((auth) => auth.account));
  if (data.parent) accounts.push(data.parent);
  dispatch(importFetchedAccounts(accounts));

  const rootId = data.root_account_id;
  if (rootId) {
    const key = `linked_notif_prefs_${rootId}`;
    try {
      const prefs = JSON.parse(localStorage.getItem(key) ?? '{}') as Record<
        string,
        { inApp?: boolean; push?: boolean }
      >;
      for (const auth of data.children) {
        const accountId = auth.target_account.id;
        prefs[accountId] = {
          ...(prefs[accountId] ?? {}),
          push: auth.push_forward,
        };
      }
      if (me && typeof data.current_push_forward === 'boolean') {
        prefs[me] = {
          ...(prefs[me] ?? {}),
          push: data.current_push_forward,
        };
      }
      localStorage.setItem(key, JSON.stringify(prefs));
    } catch {}
  }

  return data;
};

const isLatestAccountSwitchRequest = (
  getState: () => RootState,
  requestId: string,
) => getState().accountSwitches.get('latestRequestId') === requestId;

export const fetchAccountSwitches = createDataLoadingThunk(
  'accountSwitches/fetch',
  () => apiGetAccountSwitches(),
  (data, { dispatch, getState, requestId }) =>
    isLatestAccountSwitchRequest(getState, requestId)
      ? importAccountSwitches(data, dispatch)
      : data,
);

export const refreshAccountSwitches = createDataLoadingThunk(
  'accountSwitches/refresh',
  () => apiGetAccountSwitches(true).catch(() => null),
  (data, { dispatch, getState, requestId }) =>
    data && isLatestAccountSwitchRequest(getState, requestId)
      ? importAccountSwitches(data, dispatch)
      : data,
  { useLoadingBar: false },
);

export const deleteAccountSwitch = createDataLoadingThunk(
  'accountSwitches/delete',
  ({ id }: { id: string }) => apiDeleteAccountSwitch(id).then(() => id),
);

export const deleteInboundAccountSwitch = createDataLoadingThunk(
  'accountSwitches/deleteInbound',
  ({ id }: { id: string }) => apiDeleteInboundAccountSwitch(id).then(() => id),
);

export const enableLinkedPushForward = createDataLoadingThunk(
  'accountSwitches/enablePushForward',
  ({ linkedAccountId }: { linkedAccountId: string }) =>
    apiCreatePushForward(linkedAccountId),
);

export const disableLinkedPushForward = createDataLoadingThunk(
  'accountSwitches/disablePushForward',
  ({ linkedAccountId }: { linkedAccountId: string }) =>
    apiDeletePushForward(linkedAccountId).then(() => linkedAccountId),
);
