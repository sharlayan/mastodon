import { List as ImmutableList } from 'immutable';

import api from '../api';
import { me } from '../initial_state';
import { uuid } from '../uuid';

import { showAlert } from './alerts';
import { importFetchedStatus } from './importer';
import { updateTimeline } from './timelines';

export const DIRECT_COMPOSE_CHANGE = 'DIRECT_COMPOSE_CHANGE';
export const DIRECT_COMPOSE_RESET  = 'DIRECT_COMPOSE_RESET';

export const DIRECT_COMPOSE_CHANGE_SPOILER = 'DIRECT_COMPOSE_CHANGE_SPOILER';
export const DIRECT_COMPOSE_TOGGLE_SPOILER = 'DIRECT_COMPOSE_TOGGLE_SPOILER';

export const DIRECT_COMPOSE_SET_REPLY   = 'DIRECT_COMPOSE_SET_REPLY';
export const DIRECT_COMPOSE_CLEAR_REPLY = 'DIRECT_COMPOSE_CLEAR_REPLY';

export const DIRECT_COMPOSE_SUBMIT_REQUEST = 'DIRECT_COMPOSE_SUBMIT_REQUEST';
export const DIRECT_COMPOSE_SUBMIT_SUCCESS = 'DIRECT_COMPOSE_SUBMIT_SUCCESS';
export const DIRECT_COMPOSE_SUBMIT_FAIL    = 'DIRECT_COMPOSE_SUBMIT_FAIL';

export const DIRECT_COMPOSE_UPLOAD_REQUEST  = 'DIRECT_COMPOSE_UPLOAD_REQUEST';
export const DIRECT_COMPOSE_UPLOAD_PROGRESS = 'DIRECT_COMPOSE_UPLOAD_PROGRESS';
export const DIRECT_COMPOSE_UPLOAD_SUCCESS  = 'DIRECT_COMPOSE_UPLOAD_SUCCESS';
export const DIRECT_COMPOSE_UPLOAD_FAIL     = 'DIRECT_COMPOSE_UPLOAD_FAIL';
export const DIRECT_COMPOSE_UPLOAD_REMOVE   = 'DIRECT_COMPOSE_UPLOAD_REMOVE';

export const changeDirectCompose = (conversationId, text) => ({
  type: DIRECT_COMPOSE_CHANGE,
  conversationId,
  text,
});

export const resetDirectCompose = conversationId => ({
  type: DIRECT_COMPOSE_RESET,
  conversationId,
});

export const changeDirectComposeSpoiler = (conversationId, spoilerText) => ({
  type: DIRECT_COMPOSE_CHANGE_SPOILER,
  conversationId,
  spoilerText,
});

export const toggleDirectComposeSpoiler = conversationId => ({
  type: DIRECT_COMPOSE_TOGGLE_SPOILER,
  conversationId,
});

export const setDirectReplyTo = (conversationId, statusId) => ({
  type: DIRECT_COMPOSE_SET_REPLY,
  conversationId,
  statusId,
});

export const clearDirectReplyTo = conversationId => ({
  type: DIRECT_COMPOSE_CLEAR_REPLY,
  conversationId,
});

const acctsFromIds = (state, ids) =>
  ids.map(id => state.getIn(['accounts', id, 'acct'])).filter(acct => !!acct);

const acctsFromStatus = (state, statusId) => {
  const status = state.getIn(['statuses', statusId]);

  if (!status) {
    return [];
  }

  const accts = [];
  const authorAcct = state.getIn(['accounts', status.get('account'), 'acct']);

  if (status.get('account') !== me && authorAcct) {
    accts.push(authorAcct);
  }

  status.get('mentions', ImmutableList()).forEach(mention => {
    if (mention.get('id') !== me) {
      accts.push(mention.get('acct'));
    }
  });

  return accts;
};

export const submitDirectMessage = (conversationId, { inReplyToId, recipientIds }) => (dispatch, getState) => {
  const state = getState();

  if (state.getIn(['direct_compose', conversationId, 'is_submitting'])) {
    return;
  }

  const text  = (state.getIn(['direct_compose', conversationId, 'text']) || '').trim();
  const media = state.getIn(['direct_compose', conversationId, 'media'], ImmutableList());

  const spoilerActive = state.getIn(['direct_compose', conversationId, 'spoiler'], false);
  const spoilerText   = spoilerActive ? (state.getIn(['direct_compose', conversationId, 'spoiler_text']) || '').trim() : '';

  if (text.length === 0 && media.size === 0) {
    return;
  }

  let accts = acctsFromIds(state, recipientIds || []);

  if (accts.length === 0 && inReplyToId) {
    accts = acctsFromStatus(state, inReplyToId);
  }

  const mentions = [...new Set(accts)].map(acct => `@${acct}`).join(' ');
  const status   = mentions ? `${mentions} ${text}`.trim() : text;

  dispatch({ type: DIRECT_COMPOSE_SUBMIT_REQUEST, conversationId });

  api().post('/api/v1/statuses', {
    status,
    in_reply_to_id: inReplyToId || null,
    media_ids: media.map(item => item.get('id')).toArray(),
    visibility: 'direct',
    spoiler_text: spoilerText,
    sensitive: spoilerText.length > 0 || undefined,
  }, {
    headers: { 'Idempotency-Key': uuid() },
  }).then(response => {
    dispatch(importFetchedStatus({ ...response.data }));
    dispatch(updateTimeline(`conversation:${conversationId}`, { ...response.data }));
    dispatch({ type: DIRECT_COMPOSE_SUBMIT_SUCCESS, conversationId });
  }).catch(error => {
    dispatch({ type: DIRECT_COMPOSE_SUBMIT_FAIL, conversationId, error });
    dispatch(showAlert({ message: error.message }));
  });
};

export const uploadDirectMedia = (conversationId, files) => (dispatch, getState) => {
  const uploadLimit = getState().getIn(['server', 'server', 'item', 'configuration', 'statuses', 'max_media_attachments'], 4);
  const current     = getState().getIn(['direct_compose', conversationId, 'media'], ImmutableList()).size;

  if (current >= uploadLimit) {
    return;
  }

  dispatch({ type: DIRECT_COMPOSE_UPLOAD_REQUEST, conversationId });

  const file = files[0];
  const data = new FormData();
  data.append('file', file);

  api().post('/api/v2/media', data, {
    onUploadProgress: ({ loaded, total }) => {
      dispatch({ type: DIRECT_COMPOSE_UPLOAD_PROGRESS, conversationId, loaded, total });
    },
  }).then(({ status, data: media }) => {
    if (status === 200) {
      dispatch({ type: DIRECT_COMPOSE_UPLOAD_SUCCESS, conversationId, media });
    } else if (status === 202) {
      const poll = () => {
        api().get(`/api/v1/media/${media.id}`).then(response => {
          if (response.status === 200) {
            dispatch({ type: DIRECT_COMPOSE_UPLOAD_SUCCESS, conversationId, media: response.data });
          } else if (response.status === 206) {
            setTimeout(() => poll(), 1000);
          }
        }).catch(error => dispatch({ type: DIRECT_COMPOSE_UPLOAD_FAIL, conversationId, error }));
      };

      poll();
    }
  }).catch(error => {
    dispatch({ type: DIRECT_COMPOSE_UPLOAD_FAIL, conversationId, error });
  });
};

export const removeDirectMedia = (conversationId, mediaId) => ({
  type: DIRECT_COMPOSE_UPLOAD_REMOVE,
  conversationId,
  mediaId,
});
