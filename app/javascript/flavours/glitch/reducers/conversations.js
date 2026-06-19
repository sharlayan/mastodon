import { Map as ImmutableMap, List as ImmutableList } from 'immutable';

import { blockAccountSuccess, muteAccountSuccess } from 'flavours/glitch/actions/accounts';
import { blockDomainSuccess } from 'flavours/glitch/actions/domain_blocks';

import {
  CONVERSATIONS_MOUNT,
  CONVERSATIONS_UNMOUNT,
  CONVERSATIONS_FETCH_REQUEST,
  CONVERSATIONS_FETCH_SUCCESS,
  CONVERSATIONS_FETCH_FAIL,
  CONVERSATIONS_UPDATE,
  CONVERSATIONS_READ,
  CONVERSATIONS_DELETE_SUCCESS,
} from '../actions/conversations';
import { compareId } from '../compare_id';

const initialState = ImmutableMap({
  items: ImmutableList(),
  isLoading: false,
  hasMore: true,
  mounted: 0,
});

const conversationToMap = item => ImmutableMap({
  id: item.id,
  unread: item.unread,
  accounts: ImmutableList(item.accounts.map(a => a.id)),
  last_status: item.last_status ? item.last_status.id : null,
  member_ids: ImmutableList(item.member_ids || [item.id]),
});

const sameRecipients = (a, b) => a.size === b.size && a.toSet().equals(b.toSet());

const updateConversation = (state, item) => state.update('items', list => {
  const newItem  = conversationToMap(item);
  const groupIdx = list.findIndex(x => sameRecipients(x.get('accounts'), newItem.get('accounts')));

  if (groupIdx === -1) {
    return list.unshift(newItem);
  }

  const merged = list.get(groupIdx).withMutations(map => {
    const memberIds = map.get('member_ids', ImmutableList());

    if (!memberIds.includes(item.id)) {
      map.set('member_ids', memberIds.push(item.id));
    }

    map.set('unread', item.unread);

    if (item.last_status) {
      map.set('last_status', item.last_status.id);
    }
  });

  return list.delete(groupIdx).unshift(merged);
});

const expandNormalizedConversations = (state, conversations, next, isLoadingRecent) => {
  let items = ImmutableList(conversations.map(conversationToMap));

  return state.withMutations(mutable => {
    if (!items.isEmpty()) {
      mutable.update('items', list => {
        list = list.map(oldItem => {
          const newItemIndex = items.findIndex(x => sameRecipients(x.get('accounts'), oldItem.get('accounts')));

          if (newItemIndex === -1) {
            return oldItem;
          }

          const newItem = items.get(newItemIndex);
          items = items.delete(newItemIndex);

          const memberIds = oldItem.get('member_ids').toSet().union(newItem.get('member_ids').toSet()).toList();

          return newItem.set('member_ids', memberIds);
        });

        list = list.concat(items);

        return list.sortBy(x => x.get('last_status'), (a, b) => {
          if(a === null || b === null) {
            return -1;
          }

          return compareId(a, b) * -1;
        });
      });
    }

    if (!next && !isLoadingRecent) {
      mutable.set('hasMore', false);
    }

    mutable.set('isLoading', false);
  });
};

const filterConversations = (state, accountIds) => {
  return state.update('items', list => list.filterNot(item => item.get('accounts').some(accountId => accountIds.includes(accountId))));
};

export default function conversations(state = initialState, action) {
  switch (action.type) {
  case CONVERSATIONS_FETCH_REQUEST:
    return state.set('isLoading', true);
  case CONVERSATIONS_FETCH_FAIL:
    return state.set('isLoading', false);
  case CONVERSATIONS_FETCH_SUCCESS:
    return expandNormalizedConversations(state, action.conversations, action.next, action.isLoadingRecent);
  case CONVERSATIONS_UPDATE:
    return updateConversation(state, action.conversation);
  case CONVERSATIONS_MOUNT:
    return state.update('mounted', count => count + 1);
  case CONVERSATIONS_UNMOUNT:
    return state.update('mounted', count => count - 1);
  case CONVERSATIONS_READ:
    return state.update('items', list => list.map(item => {
      if (item.get('id') === action.id) {
        return item.set('unread', false);
      }

      return item;
    }));
  case blockAccountSuccess.type:
  case muteAccountSuccess.type:
    return filterConversations(state, [action.payload.relationship.id]);
  case blockDomainSuccess.type:
    return filterConversations(state, action.payload.accounts);
  case CONVERSATIONS_DELETE_SUCCESS:
    return state.update('items', list => list.filterNot(item => item.get('id') === action.id));
  default:
    return state;
  }
}
