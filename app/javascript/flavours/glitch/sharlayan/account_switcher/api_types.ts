import type { ApiAccountJSON } from 'flavours/glitch/api_types/accounts';

export interface ApiAccountSwitchAuthorizationJSON {
  id: string;
  created_at: string;
  target_account: ApiAccountJSON;
  push_forward: boolean;
  session_authorized: boolean;
  session_approval_pending: boolean;
}

export interface ApiAccountSwitchesResponseJSON {
  root_account_id: string;
  parent: ApiAccountJSON | null;
  children: ApiAccountSwitchAuthorizationJSON[];
  inbound: {
    id: string;
    created_at: string;
    account: ApiAccountJSON;
  }[];
}
