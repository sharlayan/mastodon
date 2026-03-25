import {
  apiRequestGet,
  apiRequestDelete,
  apiRequestPost,
} from 'flavours/glitch/api';
import type {
  ApiAccountSwitchesResponseJSON,
  ApiLinkedNotificationItemJSON,
} from 'flavours/glitch/api_types/account_switches';

export const apiGetAccountSwitches = () =>
  apiRequestGet<ApiAccountSwitchesResponseJSON>('v1/account_switches');

export const apiDeleteAccountSwitch = (id: string) =>
  apiRequestDelete(`v1/account_switches/${id}`);

export const apiGetLinkedNotifications = (
  sinceIds: Record<string, string> = {},
) =>
  apiRequestGet<ApiLinkedNotificationItemJSON[]>(
    'v1/account_switches/linked_notifications',
    { since_ids: sinceIds },
  );

export const apiCreatePushForward = (linkedAccountId: string) =>
  apiRequestPost<{ id: string }>('v1/account_switches/push_forward', {
    linked_account_id: linkedAccountId,
  });

export const apiDeletePushForward = (linkedAccountId: string) =>
  apiRequestDelete('v1/account_switches/push_forward', {
    linked_account_id: linkedAccountId,
  });
