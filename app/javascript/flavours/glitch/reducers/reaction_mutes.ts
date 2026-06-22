import { createReducer } from '@reduxjs/toolkit';

import {
  fetchReactionMutes,
  createReactionMute,
  deleteReactionMute,
} from 'flavours/glitch/actions/reaction_mutes';
import { reactionMutes as initialReactionMutes } from 'flavours/glitch/initial_state';
import type { ApiReactionMuteJSON } from 'flavours/glitch/initial_state';

interface ReactionMutesState {
  items: ApiReactionMuteJSON[];
  loading: boolean;
}

const initialState: ReactionMutesState = {
  items: initialReactionMutes,
  loading: false,
};

const upsert = (items: ApiReactionMuteJSON[], mute: ApiReactionMuteJSON) => {
  if (items.some((item) => item.id === mute.id)) {
    return items;
  }
  return [mute, ...items];
};

export const reactionMutesReducer = createReducer(initialState, (builder) => {
  builder
    .addCase(fetchReactionMutes.pending, (state) => {
      state.loading = true;
    })
    .addCase(fetchReactionMutes.rejected, (state) => {
      state.loading = false;
    })
    .addCase(fetchReactionMutes.fulfilled, (state, action) => {
      state.items = action.payload;
      state.loading = false;
    })
    .addCase(createReactionMute.fulfilled, (state, action) => {
      state.items = upsert(state.items, action.payload);
    })
    .addCase(deleteReactionMute.fulfilled, (state, action) => {
      state.items = state.items.filter((item) => item.id !== action.payload.id);
    });
});
