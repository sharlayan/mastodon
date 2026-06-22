import {
  apiGetCustomEmojiMutes,
  apiCreateCustomEmojiMute,
  apiDeleteCustomEmojiMute,
} from 'flavours/glitch/api/custom_emoji_mutes';
import { createDataLoadingThunk } from 'flavours/glitch/store/typed_functions';

export const fetchCustomEmojiMutes = createDataLoadingThunk(
  'custom_emoji_mutes/fetch',
  () => apiGetCustomEmojiMutes(),
);

export const createCustomEmojiMute = createDataLoadingThunk(
  'custom_emoji_mutes/create',
  ({
    prefix,
    domain,
    reject_reactions,
  }: {
    prefix: string;
    domain?: string;
    reject_reactions?: boolean;
  }) => apiCreateCustomEmojiMute({ prefix, domain, reject_reactions }),
);

export const deleteCustomEmojiMute = createDataLoadingThunk(
  'custom_emoji_mutes/delete',
  async ({ id }: { id: string }) => {
    await apiDeleteCustomEmojiMute(id);
    return { id };
  },
);
