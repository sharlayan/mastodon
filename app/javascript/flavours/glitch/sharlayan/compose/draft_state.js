import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { uuid } from 'flavours/glitch/uuid';

export const reduceStatusDraftCompose = (state, action) => {
  if (action.type === 'STATUS_DRAFT_SAVE_REQUEST') {
    return state.set('draft_save_request', action.requestId);
  }

  if (action.type === 'STATUS_DRAFT_SAVE_SUCCESS') {
    if (state.get('draft_save_request') !== action.requestId) return state;

    const params = action.draft.get('params');
    return state.withMutations(map => {
      map.set('draft_id', action.draft.get('id'));
      map.set('draft_save_request', null);
      if (params?.get('limited_scope') === 'reply' && state.get('limited_scope') === 'reply' && String(params.get('in_reply_to_id')) === String(state.get('in_reply_to'))) {
        map.set('limited_scope', 'reply');
        map.set('limited_reply_account_ids', params.get('limited_reply_account_ids'));
        if (params.get('local_only')) map.setIn(['advanced_options', 'do_not_federate'], true);
      } else if (params && state.get('limited_scope') === 'reply' && state.get('in_reply_to') && !params.get('limited_scope') && !params.get('in_reply_to_id') && params.get('visibility') === 'direct') {
        map.set('in_reply_to', null);
        map.set('reply_to_limited', false);
        map.set('privacy', 'direct');
        map.set('limited_scope', null);
        map.set('limited_reply_account_ids', null);
      }
    });
  }

  if (action.type === 'STATUS_DRAFT_SAVE_FAIL') {
    return state.get('draft_save_request') === action.requestId ? state.set('draft_save_request', null) : state;
  }

  if (action.type === 'STATUS_DRAFT_DELETE_SUCCESS') {
    return state.get('draft_id') === action.id ? state.set('draft_id', null) : state;
  }

  if (action.type !== 'COMPOSE_SET_DRAFT') return null;

  const draft = action.draft;
  const params = draft.get('params') || ImmutableMap();
  const spoilerText = params.get('spoiler_text') || '';
  const poll = params.get('poll');
  let pollState = null;

  if (poll) {
    let options = ImmutableList(poll.get('options') || []);
    if (options.size < (action.maxOptions || 4)) options = options.push('');
    pollState = ImmutableMap({
      options,
      multiple: !!poll.get('multiple'),
      expires_in: poll.get('expires_in') || 86400,
      hide_totals: !!poll.get('hide_totals'),
    });
  }

  return state.withMutations(map => {
    map.set('id', null);
    map.set('draft_id', draft.get('id'));
    map.set('draft_save_request', null);
    map.set('text', params.get('status') || '');
    map.set('spoiler', spoilerText.length > 0);
    map.set('spoiler_text', spoilerText);
    map.set('content_type', params.get('content_type') || 'text/plain');
    map.set('privacy', params.get('visibility') || 'public');
    map.set('circle_id', params.get('circle_id') || null);
    map.set('limited_scope', params.get('limited_scope') === 'reply' ? 'reply' : null);
    map.set('limited_reply_account_ids', params.get('limited_reply_account_ids') || null);
    map.set('reply_to_limited', params.get('limited_scope') === 'reply');
    map.set('clip_ids', ImmutableList(params.get('clip_ids') || []));
    map.set('in_reply_to', params.get('in_reply_to_id') || null);
    map.set('quoted_status_id', params.get('quoted_status_id') || null);
    map.set('quote_policy', params.get('quote_approval_policy') || 'public');
    map.set('scheduled_at', params.get('scheduled_at') || null);
    map.set('reaction_acceptance', params.get('reaction_acceptance') || null);
    map.set('sensitive', !!params.get('sensitive'));
    map.set('language', params.get('language') || state.get('default_language'));
    map.set('poll', pollState);
    map.set('media_attachments', draft.get('media_attachments') || ImmutableList());
    map.setIn(['advanced_options', 'do_not_federate'], !!params.get('local_only'));
    map.set('focusDate', new Date());
    map.set('idempotencyKey', uuid());
  });
};
