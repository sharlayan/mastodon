import type { Reducer } from '@reduxjs/toolkit';
import { Map as ImmutableMap } from 'immutable';

import {
  fetchClips,
  fetchAccountClips,
  fetchClip,
  fetchFavouriteClips,
  favouriteClip,
  unfavouriteClip,
  createClip,
  updateClip,
  deleteClip,
} from 'flavours/glitch/actions/clips';
import type { ApiClipJSON } from 'flavours/glitch/api_types/clips';
import { createClip as createClipFromJSON } from 'flavours/glitch/models/clip';
import type { Clip } from 'flavours/glitch/models/clip';

const initialState = ImmutableMap<string, Clip | null>();
type State = typeof initialState;

const normalizeClip = (state: State, clip: ApiClipJSON) =>
  state.set(clip.id, createClipFromJSON(clip));

const normalizeClips = (state: State, clips: ApiClipJSON[]) => {
  clips.forEach((clip) => {
    state = normalizeClip(state, clip);
  });

  return state;
};

export const clipsReducer: Reducer<State> = (state = initialState, action) => {
  if (
    createClip.fulfilled.match(action) ||
    updateClip.fulfilled.match(action) ||
    fetchClip.fulfilled.match(action) ||
    favouriteClip.fulfilled.match(action) ||
    unfavouriteClip.fulfilled.match(action)
  ) {
    return normalizeClip(state, action.payload);
  } else if (
    fetchClips.fulfilled.match(action) ||
    fetchAccountClips.fulfilled.match(action)
  ) {
    return normalizeClips(state, action.payload);
  } else if (fetchFavouriteClips.fulfilled.match(action)) {
    state = state.map((clip) => clip?.set('favourited', false) ?? null);
    return normalizeClips(state, action.payload);
  } else if (deleteClip.fulfilled.match(action)) {
    return state.set(action.meta.arg.id, null);
  } else {
    return state;
  }
};
