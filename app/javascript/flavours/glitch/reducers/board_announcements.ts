import { createReducer } from '@reduxjs/toolkit';

import {
  fetchBoardAnnouncements,
  fetchBoardAnnouncementsUnreadCount,
  readBoardAnnouncement,
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
        state.unreadCount = action.payload.filter((item) => !item.read).length;
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
      });
  },
);
