import { createAction } from '@reduxjs/toolkit';

import { importFetchedAccounts } from 'flavours/glitch/actions/importer';
import type { AppDispatch } from 'flavours/glitch/store';
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
      localStorage.setItem(key, JSON.stringify(prefs));
    } catch {}
  }

  return data;
};

export const fetchAccountSwitches = createDataLoadingThunk(
  'accountSwitches/fetch',
  () => apiGetAccountSwitches(),
  (data, { dispatch }) => importAccountSwitches(data, dispatch),
);

export const refreshAccountSwitches = createDataLoadingThunk(
  'accountSwitches/refresh',
  () => apiGetAccountSwitches(true).catch(() => null),
  (data, { dispatch }) => (data ? importAccountSwitches(data, dispatch) : null),
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
