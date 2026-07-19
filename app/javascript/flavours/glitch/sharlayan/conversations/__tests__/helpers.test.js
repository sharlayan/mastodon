import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import {
  deleteGroupedConversationMembers,
  expandGroupedConversationStatuses,
  groupedConversationParams,
  updateGroupedConversationTimeline,
} from '../actions';
import {
  mergeGroupedConversation,
  mergeGroupedConversationMemberIds,
  sharlayanConversationToMap,
} from '../reducer';

const conversation = ({
  id,
  accountIds = ['account-id'],
  unread = false,
  lastStatus = null,
  memberIds,
}) => ImmutableMap({
  id,
  accounts: ImmutableList(accountIds),
  unread,
  last_status: lastStatus,
  member_ids: ImmutableList(memberIds || [id]),
});

describe('Sharlayan grouped conversations', () => {
  it('normalizes member IDs and merges streaming updates by recipient set', () => {
    const base = ImmutableMap({ id: 'second', accounts: ImmutableList(['account-id']), unread: true, last_status: 'status-id' });
    const incoming = sharlayanConversationToMap(base, { id: 'second', member_ids: ['first', 'second'] });
    const existing = conversation({ id: 'first', unread: false, lastStatus: 'older-status' });

    expect(incoming.get('member_ids').toArray()).toEqual(['first', 'second']);
    expect(mergeGroupedConversation(ImmutableList([existing]), incoming).toJS()).toEqual([
      {
        id: 'first',
        accounts: ['account-id'],
        unread: true,
        last_status: 'status-id',
        member_ids: ['first', 'second'],
      },
    ]);
  });

  it('preserves a grouped timeline status when a streaming update has none', () => {
    const existing = conversation({ id: 'first', lastStatus: 'status-id' });
    const incoming = conversation({ id: 'second', lastStatus: null });

    expect(mergeGroupedConversation(ImmutableList([existing]), incoming).getIn([0, 'last_status'])).toBe('status-id');
    expect(mergeGroupedConversationMemberIds(existing, incoming).get('member_ids').toArray()).toEqual(['first', 'second']);
  });

  it('keeps grouped action contracts for status expansion, timeline updates, and member deletion', async () => {
    const expandTimeline = vi.fn(() => 'expanded');
    const dispatch = vi.fn();
    const updateTimeline = vi.fn(() => ({ type: 'TIMELINE_UPDATE' }));
    const getState = () => ImmutableMap({
      conversations: ImmutableMap({ items: ImmutableList([conversation({ id: 'conversation-id' })]) }),
      timelines: ImmutableMap({ 'conversation:conversation-id': ImmutableMap() }),
    });
    const api = vi.fn(() => ({ delete: vi.fn(() => Promise.resolve()) }));

    expect(groupedConversationParams('status-id')).toEqual({ max_id: 'status-id', grouped: '1' });
    expect(expandGroupedConversationStatuses(expandTimeline, 'conversation-id', { maxId: 'status-id' })).toBe('expanded');
    expect(expandTimeline).toHaveBeenCalledWith('conversation:conversation-id', '/api/v1/conversations/conversation-id/statuses', { max_id: 'status-id' });

    updateGroupedConversationTimeline({
      dispatch,
      getState,
      updateTimeline,
      conversation: { accounts: [{ id: 'account-id' }], last_status: { id: 'status-id' } },
    });
    expect(updateTimeline).toHaveBeenCalledWith('conversation:conversation-id', { id: 'status-id' });

    await deleteGroupedConversationMembers(api, ['first', 'second']);
    expect(api).toHaveBeenCalledTimes(2);
  });
});
