import { fromJS, List as ImmutableList } from 'immutable';
import { defineMessages } from 'react-intl';

import api from 'flavours/glitch/api';
import { forceLocalOnly } from 'flavours/glitch/initial_state';

import { showAlert, showAlertForError } from './alerts';
import { ensureComposeIsVisible } from './compose';

export const STATUS_DRAFTS_FETCH_REQUEST = 'STATUS_DRAFTS_FETCH_REQUEST';
export const STATUS_DRAFTS_FETCH_SUCCESS = 'STATUS_DRAFTS_FETCH_SUCCESS';
export const STATUS_DRAFTS_FETCH_FAIL = 'STATUS_DRAFTS_FETCH_FAIL';
export const STATUS_DRAFT_SAVE_SUCCESS = 'STATUS_DRAFT_SAVE_SUCCESS';
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

export const fetchStatusDrafts = () => (dispatch) => {
  dispatch({ type: STATUS_DRAFTS_FETCH_REQUEST });
  return api().get('/api/v1/status_drafts').then(({ data }) => {
    const drafts = ImmutableList(data.map(draft => fromJS(draft)));
    dispatch({ type: STATUS_DRAFTS_FETCH_SUCCESS, drafts });
    return drafts;
  }).catch(error => {
    dispatch({ type: STATUS_DRAFTS_FETCH_FAIL });
    dispatch(showAlertForError(error));
    return null;
  });
};

export const saveStatusDraft = () => (dispatch, getState) => {
  const id = getState().getIn(['compose', 'draft_id']);
  const request = id
    ? api().put(`/api/v1/status_drafts/${id}`, composePayload(getState()))
    : api().post('/api/v1/status_drafts', composePayload(getState()));

  return request.then(({ data }) => {
    dispatch({ type: STATUS_DRAFT_SAVE_SUCCESS, draft: fromJS(data) });
    dispatch(showAlert({ message: messages.saved }));
  }).catch(error => dispatch(showAlertForError(error)));
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
