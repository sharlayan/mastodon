import {
  apiRequestGet,
  apiRequestPost,
  apiRequestDelete,
} from 'flavours/glitch/api';
import type { ApiReactionMuteJSON } from 'flavours/glitch/initial_state';

export const apiGetReactionMutes = () =>
  apiRequestGet<ApiReactionMuteJSON[]>('v1/reaction_mutes');

export const apiCreateReactionMute = (params: {
  account_id?: string;
  acct?: string;
  domain?: string;
}) => apiRequestPost<ApiReactionMuteJSON>('v1/reaction_mutes', params);

export const apiDeleteReactionMute = (id: string) =>
  apiRequestDelete(`v1/reaction_mutes/${id}`);
