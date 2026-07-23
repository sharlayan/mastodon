import {
  apiCreate,
  apiUpdate,
  apiGetClips,
  apiGetAccountClips,
  apiGetClip,
  apiGetFavouriteClips,
  apiFavouriteClip,
  apiUnfavouriteClip,
  apiDeleteClip,
  apiAddStatusToClip,
  apiRemoveStatusFromClip,
} from 'flavours/glitch/api/clips';
import type { Clip } from 'flavours/glitch/models/clip';
import { createDataLoadingThunk } from 'flavours/glitch/store/typed_functions';

export const fetchClips = createDataLoadingThunk('clips/fetch', () =>
  apiGetClips(),
);

export const fetchAccountClips = createDataLoadingThunk(
  'clips/fetch_for_account',
  ({ accountId }: { accountId: string }) => apiGetAccountClips(accountId),
);

export const fetchClip = createDataLoadingThunk(
  'clip/fetch',
  ({ id }: { id: string }) => apiGetClip(id),
);

export const fetchFavouriteClips = createDataLoadingThunk(
  'clips/fetch_favourites',
  () => apiGetFavouriteClips(),
);

export const favouriteClip = createDataLoadingThunk(
  'clip/favourite',
  ({ id }: { id: string }) => apiFavouriteClip(id),
);

export const unfavouriteClip = createDataLoadingThunk(
  'clip/unfavourite',
  ({ id }: { id: string }) => apiUnfavouriteClip(id),
);

export const createClip = createDataLoadingThunk(
  'clip/create',
  (clip: Partial<Clip>) => apiCreate(clip),
);

export const updateClip = createDataLoadingThunk(
  'clip/update',
  (clip: Partial<Clip>) => apiUpdate(clip),
);

export const deleteClip = createDataLoadingThunk(
  'clip/delete',
  ({ id }: { id: string }) => apiDeleteClip(id),
);

export const addStatusToClip = createDataLoadingThunk(
  'clip/add_status',
  ({ clipId, statusId }: { clipId: string; statusId: string }) =>
    apiAddStatusToClip(clipId, statusId),
);

export const removeStatusFromClip = createDataLoadingThunk(
  'clip/remove_status',
  ({ clipId, statusId }: { clipId: string; statusId: string }) =>
    apiRemoveStatusFromClip(clipId, statusId),
);
