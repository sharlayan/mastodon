import { createReducer } from '@reduxjs/toolkit';

import {
  fetchBoardAnnouncements,
  fetchBoardAnnouncementsUnreadCount,
  readBoardAnnouncement,
  addBoardAnnouncementReaction,
  removeBoardAnnouncementReaction,
} from 'flavours/glitch/actions/board_announcements';
import type { ApiBoardAnnouncementJSON } from 'flavours/glitch/api_types/board_announcements';

interface BoardAnnouncementsState {
  items: ApiBoardAnnouncementJSON[];
  isLoading: boolean;
  loaded: boolean;
  unreadCount: number;
}

const initialState: BoardAnnouncementsState = {
  items: [],
  isLoading: false,
  loaded: false,
  unreadCount: 0,
};

const applyReaction = (
  state: BoardAnnouncementsState,
  id: string,
  name: string,
  me: boolean,
) => {
  const item = state.items.find((i) => i.id === id);

  if (!item) return;

  const reaction = item.reactions.find((r) => r.name === name);

  if (reaction) {
    if (reaction.me === me) return;
    reaction.me = me;
    reaction.count += me ? 1 : -1;

    if (reaction.count <= 0) {
      item.reactions = item.reactions.filter((r) => r.name !== name);
    }
  } else if (me) {
    item.reactions.push({ name, count: 1, me: true });
  }
};

export const boardAnnouncementsReducer = createReducer<BoardAnnouncementsState>(
  initialState,
  (builder) => {
    builder
      .addCase(fetchBoardAnnouncements.pending, (state) => {
        state.isLoading = true;
      })
      .addCase(fetchBoardAnnouncements.rejected, (state) => {
        state.isLoading = false;
      })
      .addCase(fetchBoardAnnouncements.fulfilled, (state, action) => {
        state.items = action.payload;
        state.isLoading = false;
        state.loaded = true;
        state.unreadCount = action.payload.filter(
          (item) => !item.read && !item.silence,
        ).length;
      })
      .addCase(
        fetchBoardAnnouncementsUnreadCount.fulfilled,
        (state, action) => {
          state.unreadCount = action.payload.count;
        },
      )
      .addCase(readBoardAnnouncement.fulfilled, (state, action) => {
        const item = state.items.find((i) => i.id === action.meta.arg.id);

        if (item && !item.read) {
          item.read = true;
          state.unreadCount = Math.max(0, state.unreadCount - 1);
        }
      })
      .addCase(addBoardAnnouncementReaction.pending, (state, action) => {
        applyReaction(state, action.meta.arg.id, action.meta.arg.name, true);
      })
      .addCase(addBoardAnnouncementReaction.rejected, (state, action) => {
        applyReaction(state, action.meta.arg.id, action.meta.arg.name, false);
      })
      .addCase(removeBoardAnnouncementReaction.pending, (state, action) => {
        applyReaction(state, action.meta.arg.id, action.meta.arg.name, false);
      })
      .addCase(removeBoardAnnouncementReaction.rejected, (state, action) => {
        applyReaction(state, action.meta.arg.id, action.meta.arg.name, true);
      });
  },
);
