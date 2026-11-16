import { List as ImmutableList } from 'immutable';

export const sharlayanConversationToMap = (conversation, item) =>
  conversation.set('member_ids', ImmutableList(item.member_ids || [item.id]));

export const findGroupedConversationIndex = (conversations, item) =>
  conversations.findIndex(conversation => {
    const accounts = conversation.get('accounts');
    const itemAccounts = item.get('accounts');

    return accounts.size === itemAccounts.size && accounts.toSet().equals(itemAccounts.toSet());
  });

export const mergeGroupedConversation = (conversations, item) => {
  const index = findGroupedConversationIndex(conversations, item);

  if (index === -1) return null;

  const merged = conversations.get(index).withMutations(conversation => {
    const memberIds = conversation.get('member_ids', ImmutableList());

    if (!memberIds.includes(item.get('id'))) {
      conversation.set('member_ids', memberIds.push(item.get('id')));
    }

    conversation.set('unread', item.get('unread'));

    if (item.get('last_status')) {
      conversation.set('last_status', item.get('last_status'));
    }
  });

  return conversations.delete(index).unshift(merged);
};

export const mergeGroupedConversationMemberIds = (current, incoming) =>
  incoming.set('member_ids', current.get('member_ids').toSet().union(incoming.get('member_ids').toSet()).toList());
