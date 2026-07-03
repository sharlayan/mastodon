import {
  apiRequestGet,
  apiRequestPost,
  apiRequestPut,
  apiRequestDelete,
} from 'flavours/glitch/api';
import type { ApiCustomEmojiMuteJSON } from 'flavours/glitch/initial_state';

export const apiGetCustomEmojiMutes = () =>
  apiRequestGet<ApiCustomEmojiMuteJSON[]>('v1/custom_emoji_mutes');

export const apiCreateCustomEmojiMute = (params: {
  prefix: string;
  domain?: string;
  reject_reactions?: boolean;
  hide_in_picker?: boolean;
}) => apiRequestPost<ApiCustomEmojiMuteJSON>('v1/custom_emoji_mutes', params);

export const apiDeleteCustomEmojiMute = (id: string) =>
  apiRequestDelete(`v1/custom_emoji_mutes/${id}`);

export const apiUpdateCustomEmojiMutePreferences = (params: {
  hidden: boolean;
}) =>
  apiRequestPut<{ hidden: boolean }>(
    'v1/custom_emoji_mutes/preferences',
    params,
  );
