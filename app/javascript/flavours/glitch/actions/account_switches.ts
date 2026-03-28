import { createAction } from '@reduxjs/toolkit';

import { importFetchedAccounts } from 'flavours/glitch/actions/importer';
import {
  apiGetAccountSwitches,
  apiDeleteAccountSwitch,
  apiCreatePushForward,
  apiDeletePushForward,
} from 'flavours/glitch/api/account_switches';
import { createDataLoadingThunk } from 'flavours/glitch/store/typed_functions';

export const setLinkedUnreadCounts = createAction<Record<string, number>>(
  'accountSwitches/setLinkedUnreadCounts',
);

export const fetchAccountSwitches = createDataLoadingThunk(
  'accountSwitches/fetch',
  () => apiGetAccountSwitches(),
  (data, { dispatch }) => {
    const accounts = data.children.map((auth) => auth.target_account);
    if (data.parent) accounts.push(data.parent);
    dispatch(importFetchedAccounts(accounts));
    return data;
  },
);

export const deleteAccountSwitch = createDataLoadingThunk(
  'accountSwitches/delete',
  ({ id }: { id: string }) => apiDeleteAccountSwitch(id).then(() => id),
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
