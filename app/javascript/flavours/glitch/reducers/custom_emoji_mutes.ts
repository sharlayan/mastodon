import { createReducer } from '@reduxjs/toolkit';

import {
  fetchCustomEmojiMutes,
  createCustomEmojiMute,
  deleteCustomEmojiMute,
} from 'flavours/glitch/actions/custom_emoji_mutes';
import { customEmojiMutes as initialCustomEmojiMutes } from 'flavours/glitch/initial_state';
import type { ApiCustomEmojiMuteJSON } from 'flavours/glitch/initial_state';

interface CustomEmojiMutesState {
  items: ApiCustomEmojiMuteJSON[];
  loading: boolean;
}

const initialState: CustomEmojiMutesState = {
  items: initialCustomEmojiMutes,
  loading: false,
};

const upsert = (
  items: ApiCustomEmojiMuteJSON[],
  mute: ApiCustomEmojiMuteJSON,
) => {
  if (items.some((item) => item.id === mute.id)) {
    return items;
  }
  return [mute, ...items];
};

export const customEmojiMutesReducer = createReducer(
  initialState,
  (builder) => {
    builder
      .addCase(fetchCustomEmojiMutes.pending, (state) => {
        state.loading = true;
      })
      .addCase(fetchCustomEmojiMutes.rejected, (state) => {
        state.loading = false;
      })
      .addCase(fetchCustomEmojiMutes.fulfilled, (state, action) => {
        state.items = action.payload;
        state.loading = false;
      })
      .addCase(createCustomEmojiMute.fulfilled, (state, action) => {
        state.items = upsert(state.items, action.payload);
      })
      .addCase(deleteCustomEmojiMute.fulfilled, (state, action) => {
        state.items = state.items.filter(
          (item) => item.id !== action.payload.id,
        );
      });
  },
);
