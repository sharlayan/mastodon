import { createAction } from '@reduxjs/toolkit';

import { importFetchedAccounts } from 'mastodon/actions/importer';
import { createDataLoadingThunk } from 'mastodon/store/typed_functions';

import {
  apiGetAccountSwitches,
  apiDeleteAccountSwitch,
  apiDeleteInboundAccountSwitch,
  apiCreatePushForward,
  apiDeletePushForward,
} from './api';

export const setLinkedUnreadCounts = createAction<Record<string, number>>(
  'accountSwitches/setLinkedUnreadCounts',
);
export const incrementLinkedUnreadCount = createAction<string>(
  'accountSwitches/incrementLinkedUnreadCount',
);

export const fetchAccountSwitches = createDataLoadingThunk(
  'accountSwitches/fetch',
  () => apiGetAccountSwitches(),
  (data, { dispatch }) => {
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
      } catch {
        /* ignore */
      }
    }

    return data;
  },
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
