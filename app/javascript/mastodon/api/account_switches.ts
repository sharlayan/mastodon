import { apiRequestGet, apiRequestDelete } from 'mastodon/api';
import type { ApiAccountSwitchesResponseJSON } from 'mastodon/api_types/account_switches';

export const apiGetAccountSwitches = () =>
  apiRequestGet<ApiAccountSwitchesResponseJSON>('v1/account_switches');

export const apiDeleteAccountSwitch = (id: string) =>
  apiRequestDelete(`v1/account_switches/${id}`);
