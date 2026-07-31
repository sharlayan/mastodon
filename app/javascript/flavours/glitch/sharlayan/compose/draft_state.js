import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { uuid } from 'flavours/glitch/uuid';

export const reduceStatusDraftCompose = (state, action) => {
  if (action.type === 'STATUS_DRAFT_SAVE_SUCCESS') {
    return state.set('draft_id', action.draft.get('id'));
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
    map.set('text', params.get('status') || '');
    map.set('spoiler', spoilerText.length > 0);
    map.set('spoiler_text', spoilerText);
    map.set('content_type', params.get('content_type') || 'text/plain');
    map.set('privacy', params.get('visibility') || 'public');
    map.set('circle_id', params.get('circle_id') || null);
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
