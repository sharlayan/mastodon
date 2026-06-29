import {
  apiGetBoardAnnouncements,
  apiGetBoardAnnouncementsUnreadCount,
  apiReadBoardAnnouncement,
  apiAddBoardAnnouncementReaction,
  apiRemoveBoardAnnouncementReaction,
} from 'flavours/glitch/api/board_announcements';
import { createDataLoadingThunk } from 'flavours/glitch/store/typed_functions';

export const fetchBoardAnnouncements = createDataLoadingThunk(
  'board_announcements/fetch',
  () => apiGetBoardAnnouncements(),
);

export const fetchBoardAnnouncementsUnreadCount = createDataLoadingThunk(
  'board_announcements/unread_count',
  () => apiGetBoardAnnouncementsUnreadCount(),
);

export const readBoardAnnouncement = createDataLoadingThunk(
  'board_announcements/read',
  ({ id }: { id: string }) => apiReadBoardAnnouncement(id),
  (_data, { discardLoadData }) => discardLoadData,
);

export const addBoardAnnouncementReaction = createDataLoadingThunk(
  'board_announcements/add_reaction',
  ({ id, name }: { id: string; name: string }) =>
    apiAddBoardAnnouncementReaction(id, name),
  (_data, { discardLoadData }) => discardLoadData,
);

export const removeBoardAnnouncementReaction = createDataLoadingThunk(
  'board_announcements/remove_reaction',
  ({ id, name }: { id: string; name: string }) =>
    apiRemoveBoardAnnouncementReaction(id, name),
  (_data, { discardLoadData }) => discardLoadData,
);
