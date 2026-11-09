import {
  fetchBoardAnnouncements,
  readBoardAnnouncement,
} from 'flavours/glitch/actions/board_announcements';
import type { ApiBoardAnnouncementJSON } from 'flavours/glitch/api_types/board_announcements';

import { boardAnnouncementsReducer } from '../board_announcements';

const item = (id: string, silence: boolean) =>
  ({ id, silence, read: false }) as unknown as ApiBoardAnnouncementJSON;

describe('boardAnnouncementsReducer', () => {
  it('does not decrement the unread count when a silent item is read', () => {
    const loaded = boardAnnouncementsReducer(
      undefined,
      fetchBoardAnnouncements.fulfilled(
        [item('1', false), item('2', true)],
        'request',
        undefined,
      ),
    );

    expect(loaded.unreadCount).toBe(1);

    const afterSilent = boardAnnouncementsReducer(
      loaded,
      readBoardAnnouncement.fulfilled(undefined, 'request', { id: '2' }),
    );

    expect(afterSilent.unreadCount).toBe(1);

    const afterNormal = boardAnnouncementsReducer(
      afterSilent,
      readBoardAnnouncement.fulfilled(undefined, 'request', { id: '1' }),
    );

    expect(afterNormal.unreadCount).toBe(0);
  });
});
