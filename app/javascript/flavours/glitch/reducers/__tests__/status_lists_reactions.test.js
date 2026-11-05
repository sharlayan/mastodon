import {
  REACTION_FILTER_SET,
  REACTED_STATUSES_FETCH_REQUEST,
  REACTED_STATUSES_FETCH_SUCCESS,
  REACTED_STATUSES_FETCH_FAIL,
  REACTED_STATUSES_EXPAND_SUCCESS,
  REACTED_STATUSES_EXPAND_FAIL,
} from '../../actions/reactions';
import statusLists from '../status_lists';

describe('reaction list response ownership', () => {
  it.each([
    REACTED_STATUSES_FETCH_SUCCESS,
    REACTED_STATUSES_FETCH_FAIL,
    REACTED_STATUSES_EXPAND_SUCCESS,
    REACTED_STATUSES_EXPAND_FAIL,
  ])('ignores a stale %s without changing the current list or loading state', type => {
    const state = statusLists(undefined, { type: REACTED_STATUSES_FETCH_REQUEST, requestId: 'current' });

    const result = statusLists(state, {
      type,
      requestId: 'old',
      statuses: [{ id: 'old-status' }],
      next: '/old-next',
      error: new Error('Obsolete failure'),
    });

    expect(result).toBe(state);
  });

  it('invalidates outstanding requests and the old cursor when changing filters', () => {
    const requested = statusLists(undefined, { type: REACTED_STATUSES_FETCH_REQUEST, requestId: 'old' });
    const loaded = statusLists(requested, {
      type: REACTED_STATUSES_FETCH_SUCCESS,
      requestId: 'old',
      statuses: [{ id: 'old-status' }],
      next: '/old-next',
    });

    const result = statusLists(loaded, { type: REACTION_FILTER_SET, name: '🔥' });

    expect(result.get('reactionFilter')).toBe('🔥');
    expect(result.getIn(['reactions', 'items']).isEmpty()).toBe(true);
    expect(result.getIn(['reactions', 'next'])).toBeNull();
    expect(result.getIn(['reactions', 'requestId'])).toBeNull();
    expect(result.getIn(['reactions', 'isLoading'])).toBe(false);
  });
});
