import { Set as ImmutableSet } from 'immutable';

import api, { getLinks } from '../api';

import {
  importFetchedAccounts,
  importFetchedStatuses,
  importFetchedStatus,
} from './importer';
import { expandTimeline, updateTimeline } from './timelines';

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

export const markConversationRead = (conversationId) => (dispatch) => {
  dispatch({
    type: CONVERSATIONS_READ,
    id: conversationId,
  });

  api().post(`/api/v1/conversations/${conversationId}/read`);
};

export const expandConversationStatuses = (conversationId, { maxId } = {}) =>
  expandTimeline(`conversation:${conversationId}`, `/api/v1/conversations/${conversationId}/statuses`, { max_id: maxId });

export const expandConversations = ({ maxId } = {}) => (dispatch, getState) => {
  dispatch(expandConversationsRequest());

  const params = { max_id: maxId, grouped: '1' };

  if (!maxId) {
    params.since_id = getState().getIn(['conversations', 'items', 0, 'last_status']);
  }

  const isLoadingRecent = !!params.since_id;

  api().get('/api/v1/conversations', { params })
    .then(response => {
      const next = getLinks(response).refs.find(link => link.rel === 'next');

      dispatch(importFetchedAccounts(response.data.reduce((aggr, item) => aggr.concat(item.accounts), [])));
      dispatch(importFetchedStatuses(response.data.map(item => item.last_status).filter(x => !!x)));
      dispatch(expandConversationsSuccess(response.data, next ? next.uri : null, isLoadingRecent));
    })
    .catch(err => dispatch(expandConversationsFail(err)));
};

export const expandConversationsRequest = () => ({
  type: CONVERSATIONS_FETCH_REQUEST,
});

export const expandConversationsSuccess = (conversations, next, isLoadingRecent) => ({
  type: CONVERSATIONS_FETCH_SUCCESS,
  conversations,
  next,
  isLoadingRecent,
});

export const expandConversationsFail = error => ({
  type: CONVERSATIONS_FETCH_FAIL,
  error,
});

export const updateConversations = conversation => (dispatch, getState) => {
  dispatch(importFetchedAccounts(conversation.accounts));

  if (conversation.last_status) {
    dispatch(importFetchedStatus(conversation.last_status));
  }

  dispatch({
    type: CONVERSATIONS_UPDATE,
    conversation,
  });

  if (conversation.last_status) {
    const accountIds = ImmutableSet(conversation.accounts.map(account => account.id));
    const group = getState().getIn(['conversations', 'items']).find(item => item.get('accounts').toSet().equals(accountIds));

    if (group) {
      const timelineId = `conversation:${group.get('id')}`;

      if (getState().getIn(['timelines', timelineId])) {
        dispatch(updateTimeline(timelineId, conversation.last_status));
      }
    }
  }
};

export const deleteConversation = (conversationId, memberIds = [conversationId]) => (dispatch) => {
  dispatch(deleteConversationRequest(conversationId));

  Promise.all(memberIds.map(id => api().delete(`/api/v1/conversations/${id}`)))
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
