import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { defaultContentType } from 'flavours/glitch/initial_state';
import { uuid } from 'flavours/glitch/uuid';

export const reduceScheduledCompose = (state, action) => {
  if (action.type === 'COMPOSE_SCHEDULED_AT_CHANGE') {
    return state.set('scheduled_at', action.scheduledAt);
  }

  if (action.type === 'SCHEDULED_STATUS_DELETE_SUCCESS') {
    return state.get('scheduled_at') && state.get('id') === action.id ? state.set('id', null) : state;
  }

  if (action.type !== 'COMPOSE_SET_SCHEDULED') {
    return null;
  }

  const scheduledStatus = action.scheduledStatus;
  const params = scheduledStatus.get('params') || ImmutableMap();
  const getParam = (key) => (params.get ? params.get(key) : params[key]);
  const spoilerText = getParam('spoiler_text') || '';
  const pollParam = getParam('poll');
  const mediaAttachments = scheduledStatus.get('media_attachments') || ImmutableList();
  const maxOptions = action.maxOptions || 4;

  return state.withMutations(map => {
    map.set('id', scheduledStatus.get('id'));
    map.set('draft_id', null);
    map.set('text', getParam('status') ?? getParam('text') ?? '');
    map.set('in_reply_to', getParam('in_reply_to_id') || null);
    map.set('quoted_status_id', getParam('quoted_status_id') || null);
    map.set('quote_policy', getParam('quote_approval_policy') || 'nobody');
    map.set('circle_id', getParam('circle_id') || null);
    map.set('clip_ids', ImmutableList(getParam('clip_ids') || []));
    map.set('content_type', getParam('content_type') || defaultContentType || 'text/plain');
    map.set('reaction_acceptance', getParam('reaction_acceptance') === undefined ? state.get('default_reaction_acceptance', null) : getParam('reaction_acceptance'));
    map.set('privacy', getParam('visibility') || 'public');
    map.set('media_attachments', (mediaAttachments?.size > 0 ? mediaAttachments : ImmutableList()).map(media => (media.set ? media.set('unattached', true) : media)));
    map.set('focusDate', new Date());
    map.set('caretPosition', null);
    map.set('idempotencyKey', uuid());
    map.set('sensitive', getParam('sensitive') || false);
    map.set('language', getParam('language') || state.get('default_language'));
    map.set('scheduled_at', scheduledStatus.get('scheduled_at'));
    map.setIn(['advanced_options', 'do_not_federate'], !!getParam('local_only'));
    map.set('spoiler', spoilerText.length > 0);
    map.set('spoiler_text', spoilerText);

    if (pollParam && (pollParam.options || pollParam.get?.('options'))) {
      const optionsRaw = pollParam.options ?? pollParam.get?.('options');
      const optionsArr = Array.isArray(optionsRaw) ? optionsRaw : optionsRaw?.toArray?.() ?? [];
      let options = ImmutableList(optionsArr.map(opt => (typeof opt === 'string' ? opt : (opt?.title ?? opt?.get?.('title') ?? '')))).filter(Boolean);
      if (options.size < maxOptions) options = options.push('');

      map.set('poll', ImmutableMap({
        options,
        multiple: pollParam.multiple ?? pollParam.get?.('multiple') ?? false,
        expires_in: pollParam.expires_in ?? pollParam.get?.('expires_in') ?? 24 * 3600,
        hide_totals: pollParam.hide_totals ?? pollParam.get?.('hide_totals') ?? false,
      }));
    } else {
      map.set('poll', null);
    }
  });
};
