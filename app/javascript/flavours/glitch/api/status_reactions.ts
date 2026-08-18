import api from 'flavours/glitch/api';
import type { ApiAccountJSON } from 'flavours/glitch/api_types/accounts';

export const STATUS_REACTION_ACCOUNTS_PAGE_SIZE = 40;

export interface ApiStatusReactionAccountJSON {
  id: string;
  name: string;
  url?: string;
  static_url?: string;
  domain?: string;
  is_sensitive?: boolean;
  account: ApiAccountJSON;
}

export const apiGetStatusReactionAccounts = async (
  statusId: string,
  name: string,
  maxId?: string,
) => {
  const response = await api().get<ApiStatusReactionAccountJSON[]>(
    `/api/v1/statuses/${statusId}/reacted_by`,
    {
      params: {
        name,
        max_id: maxId,
        limit: STATUS_REACTION_ACCOUNTS_PAGE_SIZE,
      },
    },
  );

  return response.data;
};
