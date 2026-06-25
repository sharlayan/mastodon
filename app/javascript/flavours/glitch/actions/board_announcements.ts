import {
  apiGetBoardAnnouncements,
  apiGetBoardAnnouncementsUnreadCount,
  apiReadBoardAnnouncement,
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
