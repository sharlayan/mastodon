import { dismissNotificationsForStatuses } from 'flavours/glitch/actions/notification_groups';

import { notificationGroupsReducer } from '../notification_groups';

const group = (id, type, statusId) => ({
  most_recent_notification_id: id,
  group_key: `ungrouped-${id}`,
  type,
  statusId,
});

const initialState = notificationGroupsReducer(undefined, { type: '@@INIT' });

describe('notification dismissal', () => {
  it('removes only successfully dismissed IDs and merges gaps in visible and pending groups', () => {
    const otherType = group('2', 'favourite', 'dm-1');
    const newerSameMessage = group('3', 'reaction', 'dm-1');
    const newMessage = group('4', 'mention', 'new-dm');
    const oldMention = group('1', 'mention', 'dm-1');
    const oldReaction = group('5', 'reaction', 'dm-1');
    const state = {
      ...initialState,
      groups: [
        { type: 'gap', maxId: '10' },
        oldMention,
        { type: 'gap', sinceId: '0' },
        otherType,
        newerSameMessage,
        newMessage,
      ],
      pendingGroups: [
        { type: 'gap', maxId: '20' },
        oldReaction,
        { type: 'gap', sinceId: '6' },
        oldMention,
        newerSameMessage,
        newMessage,
      ],
    };

    const result = notificationGroupsReducer(state, dismissNotificationsForStatuses.fulfilled(
      { notificationIds: ['1', '5'] },
      'request-1',
      ['dm-1'],
    ));

    expect(result.groups).toEqual([
      { type: 'gap', maxId: '10', sinceId: '0' },
      otherType,
      newerSameMessage,
      newMessage,
    ]);
    expect(result.pendingGroups).toEqual([
      { type: 'gap', maxId: '20', sinceId: '6' },
      newerSameMessage,
      newMessage,
    ]);
  });

  it('preserves notifications when dismissal fails', () => {
    const state = {
      ...initialState,
      groups: [group('1', 'mention', 'dm-1')],
      pendingGroups: [group('2', 'reaction', 'dm-1')],
    };

    const result = notificationGroupsReducer(state, dismissNotificationsForStatuses.rejected(
      new Error('Network error'),
      'request-1',
      ['dm-1'],
    ));

    expect(result).toBe(state);
  });
});
