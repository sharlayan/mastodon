import type { Map as ImmutableMap, List as ImmutableList } from 'immutable';

import type { Clip } from 'flavours/glitch/models/clip';
import { createAppSelector } from 'flavours/glitch/store';

const getClips = createAppSelector(
  [(state) => state.clips],
  (clips: ImmutableMap<string, Clip | null>): ImmutableList<Clip> =>
    clips.toList().filter((item: Clip | null): item is Clip => !!item),
);

export const getOrderedClips = createAppSelector(
  [(state) => getClips(state)],
  (clips) =>
    clips.sort((a: Clip, b: Clip) => a.title.localeCompare(b.title)).toArray(),
);

export const getOrderedAccountClips = createAppSelector(
  [
    getOrderedClips,
    (_state, accountId: string | null | undefined) => accountId,
  ],
  (clips, accountId) => clips.filter((clip) => clip.account_id === accountId),
);

export const getOrderedFavouriteClips = createAppSelector(
  [getOrderedClips],
  (clips) => clips.filter((clip) => clip.favourited),
);
