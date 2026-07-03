import {
  apiGetCustomEmojiMutes,
  apiCreateCustomEmojiMute,
  apiDeleteCustomEmojiMute,
  apiUpdateCustomEmojiMutePreferences,
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
    hide_in_picker,
  }: {
    prefix: string;
    domain?: string;
    reject_reactions?: boolean;
    hide_in_picker?: boolean;
  }) =>
    apiCreateCustomEmojiMute({
      prefix,
      domain,
      reject_reactions,
      hide_in_picker,
    }),
);

export const updateCustomEmojiMuteHidden = createDataLoadingThunk(
  'custom_emoji_mutes/update_hidden',
  ({ hidden }: { hidden: boolean }) =>
    apiUpdateCustomEmojiMutePreferences({ hidden }),
);

export const deleteCustomEmojiMute = createDataLoadingThunk(
  'custom_emoji_mutes/delete',
  async ({ id }: { id: string }) => {
    await apiDeleteCustomEmojiMute(id);
    return { id };
  },
);
