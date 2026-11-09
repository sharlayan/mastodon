import { fromJS, List as ImmutableList } from 'immutable';
import { defineMessages } from 'react-intl';

import api, { getLinks } from 'flavours/glitch/api';
import { forceLocalOnly } from 'flavours/glitch/initial_state';
import { uuid } from 'flavours/glitch/uuid';

import { showAlert, showAlertForError } from './alerts';
import { ensureComposeIsVisible } from './compose';

export const STATUS_DRAFTS_FETCH_REQUEST = 'STATUS_DRAFTS_FETCH_REQUEST';
export const STATUS_DRAFTS_FETCH_SUCCESS = 'STATUS_DRAFTS_FETCH_SUCCESS';
export const STATUS_DRAFTS_FETCH_FAIL = 'STATUS_DRAFTS_FETCH_FAIL';
export const STATUS_DRAFT_SAVE_REQUEST = 'STATUS_DRAFT_SAVE_REQUEST';
export const STATUS_DRAFT_SAVE_SUCCESS = 'STATUS_DRAFT_SAVE_SUCCESS';
export const STATUS_DRAFT_SAVE_FAIL = 'STATUS_DRAFT_SAVE_FAIL';
export const STATUS_DRAFT_DELETE_SUCCESS = 'STATUS_DRAFT_DELETE_SUCCESS';

const messages = defineMessages({
  saved: { id: 'status_draft.saved', defaultMessage: 'Draft saved.' },
});

const composePayload = (state) => {
  const compose = state.get('compose');
  const poll = compose.get('poll');

  return {
    status: compose.get('text'),
    spoiler_text: compose.get('spoiler') ? compose.get('spoiler_text') : '',
    content_type: compose.get('content_type'),
    local_only: forceLocalOnly || compose.getIn(['advanced_options', 'do_not_federate']),
    in_reply_to_id: compose.get('in_reply_to'),
    media_ids: compose.get('media_attachments').map(media => media.get('id')).toArray(),
    sensitive: compose.get('sensitive'),
    visibility: compose.get('circle_id') ? 'private' : compose.get('privacy'),
    circle_id: compose.get('circle_id'),
    clip_ids: compose.get('clip_ids').toArray(),
    poll: poll ? {
      options: poll.get('options').toArray(),
      expires_in: poll.get('expires_in'),
      multiple: poll.get('multiple'),
      hide_totals: poll.get('hide_totals'),
    } : null,
    language: compose.get('language'),
    quoted_status_id: compose.get('quoted_status_id'),
    quote_approval_policy: compose.get('quote_policy'),
    scheduled_at: compose.get('scheduled_at'),
    reaction_acceptance: compose.get('reaction_acceptance'),
  };
};

const MAX_DRAFT_PAGES = 5;

const fetchAllDraftPages = async () => {
  const drafts = [];
  let url = '/api/v1/status_drafts';

  for (let page = 0; url && page < MAX_DRAFT_PAGES; page++) {
    const response = await api().get(url);
    drafts.push(...response.data);
    url = getLinks(response).refs.find(link => link.rel === 'next')?.uri;
  }

  return drafts;
};

export const fetchStatusDrafts = () => (dispatch) => {
  dispatch({ type: STATUS_DRAFTS_FETCH_REQUEST });
  return fetchAllDraftPages().then((data) => {
    const drafts = ImmutableList(data.map(draft => fromJS(draft)));
    dispatch({ type: STATUS_DRAFTS_FETCH_SUCCESS, drafts });
    return drafts;
  }).catch(error => {
    dispatch({ type: STATUS_DRAFTS_FETCH_FAIL });
    dispatch(showAlertForError(error));
    return null;
  });
};

const pendingDraftSaves = new Map();

export const saveStatusDraft = () => (dispatch, getState) => {
  if (getState().getIn(['compose', 'draft_save_request'])) {
    return Promise.resolve();
  }

  const id = getState().getIn(['compose', 'draft_id']);
  const requestId = uuid();
  const payload = composePayload(getState());
  const pending = { discarded: false };

  dispatch({ type: STATUS_DRAFT_SAVE_REQUEST, requestId });

  const request = id
    ? api().put(`/api/v1/status_drafts/${id}`, payload)
    : api().post('/api/v1/status_drafts', payload);

  pending.promise = request.then(({ data }) => {
    dispatch({ type: STATUS_DRAFT_SAVE_SUCCESS, draft: fromJS(data), requestId });
    if (!pending.discarded) {
      dispatch(showAlert({ message: messages.saved }));
    }
    return data.id;
  }).catch(error => {
    dispatch({ type: STATUS_DRAFT_SAVE_FAIL, requestId });
    if (!pending.discarded) {
      dispatch(showAlertForError(error));
    }
    return null;
  }).finally(() => {
    pendingDraftSaves.delete(requestId);
  });

  pendingDraftSaves.set(requestId, pending);

  return pending.promise.then(() => undefined);
};

export const getPendingStatusDraftSave = (requestId) =>
  (requestId && pendingDraftSaves.get(requestId)) || null;

export const discardPendingStatusDraftSave = (pending, keptDraftId) => (dispatch) => {
  if (!pending) {
    return Promise.resolve();
  }

  pending.discarded = true;

  return pending.promise.then((savedDraftId) => {
    if (savedDraftId && savedDraftId !== keptDraftId) {
      return dispatch(deleteStatusDraft(savedDraftId));
    }
    return undefined;
  });
};

export const deleteStatusDraft = (id) => (dispatch) =>
  api().delete(`/api/v1/status_drafts/${id}`).then(() => {
    dispatch({ type: STATUS_DRAFT_DELETE_SUCCESS, id });
  }).catch(error => dispatch(showAlertForError(error)));

export const setComposeToStatusDraft = (draft) => (dispatch, getState) => {
  dispatch({
    type: 'COMPOSE_SET_DRAFT',
    draft,
    maxOptions: getState().getIn(['server', 'server', 'item', 'configuration', 'polls', 'max_options']),
  });
  ensureComposeIsVisible(getState);
};
