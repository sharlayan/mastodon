import type { ApiAccountJSON } from './accounts';

export interface ApiAccountSwitchAuthorizationJSON {
  id: string;
  created_at: string;
  target_account: ApiAccountJSON;
}

export interface ApiAccountSwitchesResponseJSON {
  parent: ApiAccountJSON | null;
  children: ApiAccountSwitchAuthorizationJSON[];
}
