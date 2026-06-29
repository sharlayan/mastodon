import {
  apiRequestGet,
  apiRequestPost,
  apiRequestPut,
  apiRequestDelete,
} from 'flavours/glitch/api';
import type {
  ApiBoardAnnouncementJSON,
  ApiBoardAnnouncementUnreadCountJSON,
} from 'flavours/glitch/api_types/board_announcements';

export const apiGetBoardAnnouncements = () =>
  apiRequestGet<ApiBoardAnnouncementJSON[]>('v1/board_announcements');

export const apiGetBoardAnnouncementsUnreadCount = () =>
  apiRequestGet<ApiBoardAnnouncementUnreadCountJSON>(
    'v1/board_announcements/unread_count',
  );

export const apiReadBoardAnnouncement = (id: string) =>
  apiRequestPost(`v1/board_announcements/${id}/read`);

export const apiAddBoardAnnouncementReaction = (id: string, name: string) =>
  apiRequestPut(
    `v1/board_announcements/${id}/reactions/${encodeURIComponent(name)}`,
  );

export const apiRemoveBoardAnnouncementReaction = (id: string, name: string) =>
  apiRequestDelete(
    `v1/board_announcements/${id}/reactions/${encodeURIComponent(name)}`,
  );
