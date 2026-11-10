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
  it('does not report an unfetched reaction list as settled', () => {
    expect(statusLists(undefined, { type: '@@INIT' }).getIn(['reactions', 'isLoading'])).toBeUndefined();
  });

  it('ignores stale fetch and expand responses without changing the current list or loading state', () => {
    const state = statusLists(undefined, { type: REACTED_STATUSES_FETCH_REQUEST, requestId: 'current' });
    const types = [
      REACTED_STATUSES_FETCH_SUCCESS,
      REACTED_STATUSES_FETCH_FAIL,
      REACTED_STATUSES_EXPAND_SUCCESS,
      REACTED_STATUSES_EXPAND_FAIL,
    ];

    expect(types.filter(type => statusLists(state, {
      type,
      requestId: 'old',
      statuses: [{ id: 'old-status' }],
      next: '/old-next',
      error: new Error('Obsolete failure'),
    }) !== state)).toEqual([]);
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
    expect(result.getIn(['reactions', 'isLoading'])).toBeUndefined();
  });
});
