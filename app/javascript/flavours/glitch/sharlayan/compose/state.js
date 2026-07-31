import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { reduceScheduledCompose } from './scheduled_state';
import { reduceStatusDraftCompose } from './draft_state';

export const sharlayanComposeInitialState = ImmutableMap({
  circle_id: null,
  clip_ids: ImmutableList(),
  scheduled_at: null,
  draft_id: null,
  reaction_acceptance: null,
  default_reaction_acceptance: null,
});

export const resetSharlayanComposeState = (state) =>
  state.merge(sharlayanComposeInitialState)
    .set('default_reaction_acceptance', state.get('default_reaction_acceptance', null))
    .set('reaction_acceptance', state.get('default_reaction_acceptance', null));

export const resetScheduledComposeState = (state) =>
  state.set('scheduled_at', null);

export const discardCompose = () => ({
  type: 'COMPOSE_DISCARD',
});

export const changeScheduledAt = (scheduledAt) => ({
  type: 'COMPOSE_SCHEDULED_AT_CHANGE',
  scheduledAt: scheduledAt || null,
});

export const changeReactionAcceptance = (reactionAcceptance) => ({
  type: 'COMPOSE_REACTION_ACCEPTANCE_CHANGE',
  reactionAcceptance,
});

export const reduceSharlayanCompose = (
  state,
  action,
  { createIdempotencyKey, resetCompose },
) => {
  const scheduledState = reduceScheduledCompose(state, action);
  if (scheduledState) return scheduledState;
  const draftState = reduceStatusDraftCompose(state, action);
  if (draftState) return draftState;

  if (action.type === 'compose/circle_change') {
    return state
      .set('circle_id', action.payload)
      .set('idempotencyKey', createIdempotencyKey());
  }

  if (action.type === 'compose/clip_toggle') {
    return state.update('clip_ids', list => (
      list.includes(action.payload)
        ? list.filter(id => id !== action.payload)
        : list.push(action.payload)
    ));
  }

  if (action.type === 'COMPOSE_REACTION_ACCEPTANCE_CHANGE') {
    return state.set('reaction_acceptance', action.reactionAcceptance);
  }

  if (action.type === 'COMPOSE_DISCARD') {
    return resetCompose(state).setIn(['advanced_options', 'threaded_mode'], false);
  }

  return null;
};
