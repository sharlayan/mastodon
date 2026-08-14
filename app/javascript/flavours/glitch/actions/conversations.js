import api, { getLinks } from '../api';

import {
  importFetchedAccounts,
  importFetchedStatuses,
  importFetchedStatus,
} from './importer';
import { expandTimeline, updateTimeline } from './timelines';
import {
  deleteGroupedConversationMembers,
  expandGroupedConversationStatuses,
  groupedConversationParams,
  updateGroupedConversationTimeline,
} from '../sharlayan/conversations/actions';

export const CONVERSATIONS_MOUNT   = 'CONVERSATIONS_MOUNT';
export const CONVERSATIONS_UNMOUNT = 'CONVERSATIONS_UNMOUNT';

export const CONVERSATIONS_FETCH_REQUEST = 'CONVERSATIONS_FETCH_REQUEST';
export const CONVERSATIONS_FETCH_SUCCESS = 'CONVERSATIONS_FETCH_SUCCESS';
export const CONVERSATIONS_FETCH_FAIL    = 'CONVERSATIONS_FETCH_FAIL';
export const CONVERSATIONS_UPDATE        = 'CONVERSATIONS_UPDATE';

export const CONVERSATIONS_READ = 'CONVERSATIONS_READ';

export const CONVERSATIONS_DELETE_REQUEST = 'CONVERSATIONS_DELETE_REQUEST';
export const CONVERSATIONS_DELETE_SUCCESS = 'CONVERSATIONS_DELETE_SUCCESS';
export const CONVERSATIONS_DELETE_FAIL    = 'CONVERSATIONS_DELETE_FAIL';

export const mountConversations = () => ({
  type: CONVERSATIONS_MOUNT,
});

export const unmountConversations = () => ({
  type: CONVERSATIONS_UNMOUNT,
});

export const markConversationRead = (conversationId, preserveGroup = false) => (dispatch) => {
  dispatch({
    type: CONVERSATIONS_READ,
    id: conversationId,
  });

  api().post(`/api/v1/conversations/${conversationId}/read`, null, { params: { preserve_group: preserveGroup || undefined } });
};

export const expandConversationStatuses = (conversationId, { maxId, preserveGroup = false } = {}) =>
  expandGroupedConversationStatuses(expandTimeline, conversationId, { maxId, preserveGroup });

export const expandConversations = ({ maxId, replace = false } = {}) => (dispatch, getState) => {
  dispatch(expandConversationsRequest());

  const preserveGroup = getState().getIn(['settings', 'direct', 'preserve_group_on_new_mentions'], false);
  const params = groupedConversationParams(maxId, preserveGroup);

  if (!maxId && !preserveGroup && !replace) {
    params.since_id = getState().getIn(['conversations', 'items', 0, 'last_status']);
  }

  const isLoadingRecent = !!params.since_id;
  const replaceItems = !maxId && (preserveGroup || replace);

  api().get('/api/v1/conversations', { params })
    .then(response => {
      const next = getLinks(response).refs.find(link => link.rel === 'next');

      dispatch(importFetchedAccounts(response.data.reduce((aggr, item) => aggr.concat(item.accounts), [])));
      dispatch(importFetchedStatuses(response.data.map(item => item.last_status).filter(x => !!x)));
      dispatch(expandConversationsSuccess(response.data, next ? next.uri : null, isLoadingRecent, replaceItems));
    })
    .catch(err => dispatch(expandConversationsFail(err)));
};

export const expandConversationsRequest = () => ({
  type: CONVERSATIONS_FETCH_REQUEST,
});

export const expandConversationsSuccess = (conversations, next, isLoadingRecent, replace = false) => ({
  type: CONVERSATIONS_FETCH_SUCCESS,
  conversations,
  next,
  isLoadingRecent,
  replace,
});

export const expandConversationsFail = error => ({
  type: CONVERSATIONS_FETCH_FAIL,
  error,
});

export const updateConversations = conversation => (dispatch, getState) => {
  if (getState().getIn(['settings', 'direct', 'preserve_group_on_new_mentions'], false)) {
    const accountIds = new Set(conversation.accounts.map(account => account.id));
    const expandedGroup = getState().getIn(['conversations', 'items']).some(item => (
      item.get('accounts').size < accountIds.size && item.get('accounts').every(accountId => accountIds.has(accountId))
    ));

    if (expandedGroup) {
      dispatch(expandConversations());
      return;
    }
  }

  dispatch(importFetchedAccounts(conversation.accounts));

  if (conversation.last_status) {
    dispatch(importFetchedStatus(conversation.last_status));
  }

  dispatch({
    type: CONVERSATIONS_UPDATE,
    conversation,
  });

  updateGroupedConversationTimeline({ dispatch, getState, updateTimeline, conversation });
};

export const deleteConversation = (conversationId, memberIds = [conversationId]) => (dispatch) => {
  dispatch(deleteConversationRequest(conversationId));

  deleteGroupedConversationMembers(api, memberIds)
    .then(() => dispatch(deleteConversationSuccess(conversationId)))
    .catch(error => dispatch(deleteConversationFail(conversationId, error)));
};

export const deleteConversationRequest = id => ({
  type: CONVERSATIONS_DELETE_REQUEST,
  id,
});

export const deleteConversationSuccess = id => ({
  type: CONVERSATIONS_DELETE_SUCCESS,
  id,
});

export const deleteConversationFail = (id, error) => ({
  type: CONVERSATIONS_DELETE_FAIL,
  id,
  error,
});
