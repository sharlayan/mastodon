import type { AxiosResponse } from 'axios';

import api, {
  getLinks,
  apiRequestPost,
  apiRequestPut,
  apiRequestGet,
  apiRequestDelete,
} from 'flavours/glitch/api';
import type { ApiClipJSON } from 'flavours/glitch/api_types/clips';

export const apiCreate = (clip: Partial<ApiClipJSON>) =>
  apiRequestPost<ApiClipJSON>('v1/clips', clip);

export const apiUpdate = (clip: Partial<ApiClipJSON>) =>
  apiRequestPut<ApiClipJSON>(`v1/clips/${clip.id}`, clip);

export const apiGetClips = () => apiRequestGet<ApiClipJSON[]>('v1/clips');

export const apiGetAccountClips = (accountId: string) =>
  apiRequestGet<ApiClipJSON[]>(`v1/accounts/${accountId}/clips`);

export const apiGetClip = (clipId: string) =>
  apiRequestGet<ApiClipJSON>(`v1/clips/${clipId}`);

export const apiGetFavouriteClips = async () => {
  const clips: ApiClipJSON[] = [];
  let url: string | undefined = '/api/v1/clips/favourites';

  while (url) {
    const response: AxiosResponse<ApiClipJSON[]> = await api().get(url);
    clips.push(...response.data);
    url = getLinks(response).refs.find((link) => link.rel === 'next')?.uri;
  }

  return clips;
};

export const apiFavouriteClip = (clipId: string) =>
  apiRequestPost<ApiClipJSON>(`v1/clips/${clipId}/favourite`);

export const apiUnfavouriteClip = (clipId: string) =>
  apiRequestPost<ApiClipJSON>(`v1/clips/${clipId}/unfavourite`);

export const apiGetStatusClips = (statusId: string) =>
  apiRequestGet<ApiClipJSON[]>(`v1/statuses/${statusId}/clips`);

export const apiDeleteClip = (clipId: string) =>
  apiRequestDelete(`v1/clips/${clipId}`);

export const apiAddStatusToClip = (clipId: string, statusId: string) =>
  apiRequestPost(`v1/clips/${clipId}/statuses`, {
    status_id: statusId,
  });

export const apiRemoveStatusFromClip = (clipId: string, statusId: string) =>
  apiRequestDelete(`v1/clips/${clipId}/statuses/${statusId}`);
