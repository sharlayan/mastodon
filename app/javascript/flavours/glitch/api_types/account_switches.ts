import type { ApiAccountJSON } from './accounts';

export interface ApiAccountSwitchAuthorizationJSON {
  id: string;
  created_at: string;
  target_account: ApiAccountJSON;
}

export interface ApiAccountSwitchesResponseJSON {
  root_account_id: string;
  parent: ApiAccountJSON | null;
  children: ApiAccountSwitchAuthorizationJSON[];
}
