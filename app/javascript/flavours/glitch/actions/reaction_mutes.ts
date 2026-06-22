import {
  apiGetReactionMutes,
  apiCreateReactionMute,
  apiDeleteReactionMute,
} from 'flavours/glitch/api/reaction_mutes';
import { createDataLoadingThunk } from 'flavours/glitch/store/typed_functions';

export const fetchReactionMutes = createDataLoadingThunk(
  'reaction_mutes/fetch',
  () => apiGetReactionMutes(),
);

export const createReactionMute = createDataLoadingThunk(
  'reaction_mutes/create',
  ({
    account_id,
    acct,
    domain,
  }: {
    account_id?: string;
    acct?: string;
    domain?: string;
  }) => apiCreateReactionMute({ account_id, acct, domain }),
);

export const deleteReactionMute = createDataLoadingThunk(
  'reaction_mutes/delete',
  async ({ id }: { id: string }) => {
    await apiDeleteReactionMute(id);
    return { id };
  },
);
