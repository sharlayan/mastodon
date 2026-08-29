import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import {
  COMPOSE_DIRECT,
  COMPOSE_MENTION,
} from '@/flavours/glitch/actions/compose';
import {
  changeComposeCircle,
  toggleComposeClip,
} from '@/flavours/glitch/actions/compose_typed';

import { composeReducer } from '../../../reducers/compose';
import {
  changeScheduledAt,
  changeReactionAcceptance,
  discardCompose,
  resetScheduledComposeState,
  resetSharlayanComposeState,
  sharlayanComposeInitialState,
} from '../state';

describe('Sharlayan compose state', () => {
  it('provides isolated defaults and resets them without changing core state', () => {
    const state = ImmutableMap({
      circle_id: 'circle-id',
      clip_ids: ImmutableList(['clip-id']),
      scheduled_at: '2026-07-18T01:00:00Z',
      text: 'keep me',
    });

    expect(sharlayanComposeInitialState.toJS()).toEqual({
      circle_id: null,
      clip_ids: [],
      scheduled_at: null,
      draft_id: null,
      reaction_acceptance: null,
      default_reaction_acceptance: null,
    });
    expect(resetSharlayanComposeState(state).toJS()).toEqual({
      circle_id: null,
      clip_ids: [],
      scheduled_at: null,
      draft_id: null,
      reaction_acceptance: null,
      default_reaction_acceptance: null,
      text: 'keep me',
    });
    expect(resetScheduledComposeState(state).get('circle_id')).toBe('circle-id');
    expect(resetScheduledComposeState(state).get('clip_ids').toArray()).toEqual(['clip-id']);
    expect(resetScheduledComposeState(state).get('scheduled_at')).toBeNull();
  });

  it('changes and resets reaction acceptance', () => {
    let state = composeReducer(undefined, changeReactionAcceptance('likeOnly'));
    expect(state.get('reaction_acceptance')).toBe('likeOnly');

    state = composeReducer(state, discardCompose());
    expect(state.get('reaction_acceptance')).toBeNull();
  });

  it('restores the server default reaction acceptance after discard', () => {
    const state = composeReducer(undefined, discardCompose())
      .set('default_reaction_acceptance', 'likeOnlyForRemote')
      .set('reaction_acceptance', 'likeOnly');

    expect(composeReducer(state, discardCompose()).get('reaction_acceptance')).toBe('likeOnlyForRemote');
  });

  it('handles circle and clip selection through the core reducer hook', () => {
    let state = composeReducer(undefined, changeComposeCircle('circle-id'));
    const firstKey = state.get('idempotencyKey');

    expect(state.get('circle_id')).toBe('circle-id');

    state = composeReducer(state, toggleComposeClip('clip-id'));
    expect(state.get('clip_ids').toArray()).toEqual(['clip-id']);

    state = composeReducer(state, toggleComposeClip('clip-id'));
    expect(state.get('clip_ids').toArray()).toEqual([]);

    state = composeReducer(state, changeComposeCircle(null));
    expect(state.get('circle_id')).toBeNull();
    expect(state.get('idempotencyKey')).not.toBe(firstKey);
  });

  it('keeps the public schedule and discard action contracts', () => {
    let state = composeReducer(undefined, changeScheduledAt('2026-07-18T01:00:00Z'));
    state = state
      .set('text', 'draft')
      .set('in_reply_to', 'status-id')
      .set('media_attachments', ImmutableList(['media-id']))
      .set('circle_id', 'circle-id')
      .set('clip_ids', ImmutableList(['clip-id']))
      .setIn(['advanced_options', 'threaded_mode'], true);

    expect(state.get('scheduled_at')).toBe('2026-07-18T01:00:00Z');

    state = composeReducer(state, discardCompose());
    expect(state.get('text')).toBe('');
    expect(state.get('in_reply_to')).toBeNull();
    expect(state.get('media_attachments')).toEqual(ImmutableList());
    expect(state.get('circle_id')).toBeNull();
    expect(state.get('clip_ids')).toEqual(ImmutableList());
    expect(state.get('scheduled_at')).toBeNull();
    expect(state.getIn(['advanced_options', 'threaded_mode'])).toBe(false);
  });

  it.each([COMPOSE_MENTION, COMPOSE_DIRECT])('leaves threaded mode when starting a mention with %s', (type) => {
    const state = composeReducer(undefined, { type: '@@INIT' })
      .setIn(['advanced_options', 'threaded_mode'], true);

    const nextState = composeReducer(state, {
      type,
      account: ImmutableMap({ acct: 'alice' }),
    });

    expect(nextState.getIn(['advanced_options', 'threaded_mode'])).toBe(false);
  });

  it('only clears scheduling metadata on a regular compose reset', () => {
    let state = composeReducer(undefined, changeComposeCircle('circle-id'))
      .set('clip_ids', ImmutableList(['clip-id']))
      .set('scheduled_at', '2026-07-18T01:00:00Z');

    state = composeReducer(state, { type: 'COMPOSE_RESET' });

    expect(state.get('circle_id')).toBe('circle-id');
    expect(state.get('clip_ids').toArray()).toEqual(['clip-id']);
    expect(state.get('scheduled_at')).toBeNull();
  });
});
