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

export interface ApiLinkedNotificationAccountJSON {
  id: string;
  acct: string;
  display_name: string;
  username: string;
  avatar: string;
}

export interface ApiLinkedNotificationJSON {
  id: string;
  type: string;
  created_at: string;
  account: ApiLinkedNotificationAccountJSON;
}

export interface ApiLinkedNotificationItemJSON {
  linked_account_id: string;
  linked_account_acct: string;
  notification: ApiLinkedNotificationJSON;
}
