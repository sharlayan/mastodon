import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import {
  changeComposeCircle,
  toggleComposeClip,
} from '@/flavours/glitch/actions/compose_typed';

import { composeReducer } from '../../../reducers/compose';
import {
  changeScheduledAt,
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
    });
    expect(resetSharlayanComposeState(state).toJS()).toEqual({
      circle_id: null,
      clip_ids: [],
      scheduled_at: null,
      text: 'keep me',
    });
    expect(resetScheduledComposeState(state).get('circle_id')).toBe('circle-id');
    expect(resetScheduledComposeState(state).get('clip_ids').toArray()).toEqual(['clip-id']);
    expect(resetScheduledComposeState(state).get('scheduled_at')).toBeNull();
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
      .setIn(['advanced_options', 'threaded_mode'], true);

    expect(state.get('scheduled_at')).toBe('2026-07-18T01:00:00Z');

    state = composeReducer(state, discardCompose());
    expect(state.get('text')).toBe('');
    expect(state.get('scheduled_at')).toBeNull();
    expect(state.getIn(['advanced_options', 'threaded_mode'])).toBe(false);
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
