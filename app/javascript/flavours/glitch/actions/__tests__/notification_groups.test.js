import { apiDismissNotification } from 'flavours/glitch/api/notifications';

import { dismissNotificationsForStatuses } from '../notification_groups';

vi.mock('flavours/glitch/api/notifications', () => ({
  apiClearNotifications: vi.fn(),
  apiDismissNotification: vi.fn(),
  apiFetchNotificationGroups: vi.fn(),
}));

const group = (id, type, statusId) => ({
  most_recent_notification_id: id,
  type,
  statusId,
});

describe('dismissNotificationsForStatuses', () => {
  beforeEach(() => {
    vi.mocked(apiDismissNotification).mockReset();
    vi.mocked(apiDismissNotification).mockResolvedValue(undefined);
  });

  it('dismisses matching messages and reactions from visible and pending groups once each', async () => {
    const notificationGroups = {
      groups: [
        group('1', 'mention', 'dm-1'),
        group('2', 'quote', 'dm-1'),
        group('3', 'favourite', 'dm-1'),
        group('4', 'mention', 'other-dm'),
        { type: 'gap' },
      ],
      pendingGroups: [
        group('1', 'mention', 'dm-1'),
        group('5', 'reaction', 'dm-1'),
        group('6', 'status', 'dm-1'),
      ],
    };

    const result = await dismissNotificationsForStatuses(['dm-1'])(vi.fn(), () => ({ notificationGroups }));

    expect(result.payload).toEqual({ notificationIds: ['1', '2', '5'] });
    expect(apiDismissNotification.mock.calls).toEqual([['1'], ['2'], ['5']]);
  });

  it('returns only the notification IDs selected before the API request started', async () => {
    let completeRequest;
    vi.mocked(apiDismissNotification).mockReturnValue(new Promise(resolve => { completeRequest = resolve; }));
    const notificationGroups = { groups: [group('1', 'mention', 'dm-1')], pendingGroups: [] };

    const request = dismissNotificationsForStatuses(['dm-1'])(vi.fn(), () => ({ notificationGroups }));
    notificationGroups.groups.push(group('2', 'reaction', 'dm-1'));
    notificationGroups.pendingGroups.push(group('3', 'mention', 'new-dm'));
    completeRequest();
    const result = await request;

    expect(result.payload).toEqual({ notificationIds: ['1'] });
    expect(apiDismissNotification.mock.calls).toEqual([['1']]);
  });

  it('rejects without a fulfilled action when an API request fails', async () => {
    vi.mocked(apiDismissNotification).mockRejectedValue(new Error('Network error'));
    const notificationGroups = { groups: [group('1', 'mention', 'dm-1')], pendingGroups: [] };
    const dispatch = vi.fn();

    const result = await dismissNotificationsForStatuses(['dm-1'])(dispatch, () => ({ notificationGroups }));

    expect(dismissNotificationsForStatuses.rejected.match(result)).toBe(true);
    expect(dispatch.mock.calls.some(([action]) => dismissNotificationsForStatuses.fulfilled.match(action))).toBe(false);
  });

  it('leaves unrelated notifications alone when no matching message is loaded', async () => {
    const notificationGroups = {
      groups: [group('1', 'favourite', 'dm-1')],
      pendingGroups: [group('2', 'mention', 'other-dm')],
    };

    const result = await dismissNotificationsForStatuses(['dm-1'])(vi.fn(), () => ({ notificationGroups }));

    expect(result.payload).toEqual({ notificationIds: [] });
    expect(apiDismissNotification).not.toHaveBeenCalled();
  });
});
