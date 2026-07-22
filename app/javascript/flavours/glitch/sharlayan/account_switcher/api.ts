import {
  apiRequestGet,
  apiRequestDelete,
  apiRequestPost,
} from 'flavours/glitch/api';

import type { ApiAccountSwitchesResponseJSON } from './api_types';

export const apiGetAccountSwitches = () =>
  apiRequestGet<ApiAccountSwitchesResponseJSON>('v1/account_switches');

export const apiDeleteAccountSwitch = (id: string) =>
  apiRequestDelete(`v1/account_switches/${id}`);

export const apiDeleteInboundAccountSwitch = (id: string) =>
  apiRequestDelete(`v1/account_switches/${id}/inbound`);

export const apiGetLinkedUnreadCounts = () =>
  apiRequestGet<Record<string, number>>(
    'v1/account_switches/linked_unread_counts',
  );

export const apiCreatePushForward = (linkedAccountId: string) =>
  apiRequestPost<{ id: string }>('v1/account_switches/push_forward', {
    linked_account_id: linkedAccountId,
  });

export const apiDeletePushForward = (linkedAccountId: string) =>
  apiRequestDelete('v1/account_switches/push_forward', {
    linked_account_id: linkedAccountId,
  });
