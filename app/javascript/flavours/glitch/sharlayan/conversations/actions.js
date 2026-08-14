import { Set as ImmutableSet } from 'immutable';

export const groupedConversationParams = (maxId, preserveGroup = false) => ({
  max_id: maxId,
  grouped: '1',
  ...(preserveGroup ? { preserve_group: '1' } : {}),
});

export const expandGroupedConversationStatuses = (expandTimeline, conversationId, { maxId, preserveGroup = false } = {}) =>
  expandTimeline(`conversation:${conversationId}`, `/api/v1/conversations/${conversationId}/statuses`, { max_id: maxId, ...(preserveGroup ? { preserve_group: '1' } : {}) });

export const updateGroupedConversationTimeline = ({ dispatch, getState, updateTimeline, conversation }) => {
  if (!conversation.last_status) return;

  const accountIds = ImmutableSet(conversation.accounts.map(account => account.id));
  const group = getState().getIn(['conversations', 'items']).find(item => item.get('accounts').toSet().equals(accountIds));
  const timelineId = group && `conversation:${group.get('id')}`;

  if (timelineId && getState().getIn(['timelines', timelineId])) {
    dispatch(updateTimeline(timelineId, conversation.last_status));
  }
};

export const deleteGroupedConversationMembers = (api, memberIds) =>
  Promise.all(memberIds.map(id => api().delete(`/api/v1/conversations/${id}`)));
