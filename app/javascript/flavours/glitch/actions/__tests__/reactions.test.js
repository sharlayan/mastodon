import { Map as ImmutableMap } from 'immutable';

import api, { getLinks } from 'flavours/glitch/api';

import statusLists from '../../reducers/status_lists';
import { importFetchedStatuses } from '../importer';
import {
  REACTION_FILTER_SET,
  REACTED_STATUSES_FETCH_FAIL,
  REACTED_STATUSES_EXPAND_FAIL,
  expandReactedStatuses,
  fetchReactedStatuses,
  setReactionFilter,
} from '../reactions';

vi.mock('flavours/glitch/api', () => ({ default: vi.fn(), getLinks: vi.fn() }));
vi.mock('../importer', () => ({
  importFetchedStatuses: vi.fn(statuses => ({ type: 'TEST_IMPORT_STATUSES', statuses })),
}));

const apiGet = vi.fn();
const response = (id, next = null) => ({ data: [{ id }], next });
const deferred = () => {
  let resolveRequest;
  let rejectRequest;
  const promise = new Promise((resolve, reject) => { resolveRequest = resolve; rejectRequest = reject; });
  return { promise, resolve: resolveRequest, reject: rejectRequest };
};
const flushResponses = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

const makeStore = () => {
  let state = statusLists(undefined, { type: '@@INIT' });
  const getState = () => ImmutableMap({ status_lists: state });
  const dispatch = vi.fn(action => {
    if (typeof action === 'function') return action(dispatch, getState);
    state = statusLists(state, action);
    return action;
  });
  return { dispatch, lists: () => state };
};

beforeEach(() => {
  vi.clearAllMocks();
  apiGet.mockReset();
  vi.mocked(api).mockReturnValue({ get: apiGet });
  vi.mocked(getLinks).mockImplementation(result => ({ refs: result.next ? [{ rel: 'next', uri: result.next }] : [] }));
});

describe('reaction list requests', () => {
  it('loads a newly selected filter immediately and ignores the previous response', async () => {
    const old = deferred();
    const current = deferred();
    apiGet.mockReturnValueOnce(old.promise).mockReturnValueOnce(current.promise);
    const store = makeStore();

    store.dispatch(fetchReactedStatuses());
    store.dispatch(setReactionFilter('🔥'));

    expect(apiGet.mock.calls).toEqual([
      ['/api/v1/reactions', { params: {} }],
      ['/api/v1/reactions', { params: { name: '🔥' } }],
    ]);
    current.resolve(response('current', '/current-next'));
    await flushResponses();
    old.resolve(response('old', '/old-next'));
    await flushResponses();

    expect(store.lists().getIn(['reactions', 'items']).toArray()).toEqual(['current']);
    expect(store.lists().getIn(['reactions', 'next'])).toBe('/current-next');
    expect(importFetchedStatuses.mock.calls).toEqual([[response('current').data]]);
  });

  it('keeps the newest request when a filter is reselected before older requests finish', async () => {
    const first = deferred();
    const second = deferred();
    const newest = deferred();
    apiGet.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise).mockReturnValueOnce(newest.promise);
    const store = makeStore();

    store.dispatch(setReactionFilter('🔥'));
    store.dispatch(setReactionFilter('👍'));
    store.dispatch(setReactionFilter('🔥'));
    expect(apiGet).toHaveBeenCalledTimes(3);

    newest.resolve(response('newest'));
    await flushResponses();
    first.resolve(response('first'));
    second.resolve(response('second'));
    await flushResponses();

    expect(store.lists().get('reactionFilter')).toBe('🔥');
    expect(store.lists().getIn(['reactions', 'items']).toArray()).toEqual(['newest']);
  });

  it('does not end the current loading state or dispatch an error for an obsolete failure', async () => {
    const old = deferred();
    const current = deferred();
    apiGet.mockReturnValueOnce(old.promise).mockReturnValueOnce(current.promise);
    const store = makeStore();

    store.dispatch(fetchReactedStatuses());
    store.dispatch(setReactionFilter('🔥'));
    old.reject(new Error('Obsolete request failed'));
    await flushResponses();

    expect(store.lists().getIn(['reactions', 'isLoading'])).toBe(true);
    expect(store.dispatch.mock.calls.some(([action]) => action.type === REACTED_STATUSES_FETCH_FAIL)).toBe(false);
    current.resolve(response('current'));
    await flushResponses();
  });

  it.each(['resolve', 'reject'])('ignores an obsolete pagination request that finishes with %s', async finish => {
    apiGet.mockResolvedValueOnce(response('old-first', '/old-next'));
    const oldPage = deferred();
    const current = deferred();
    apiGet.mockReturnValueOnce(oldPage.promise).mockReturnValueOnce(current.promise);
    const store = makeStore();
    store.dispatch(fetchReactedStatuses());
    await flushResponses();

    store.dispatch(expandReactedStatuses());
    store.dispatch(setReactionFilter('🔥'));
    if (finish === 'resolve') oldPage.resolve(response('old-page', '/old-more'));
    else oldPage.reject(new Error('Obsolete page failed'));
    await flushResponses();

    expect(store.lists().getIn(['reactions', 'isLoading'])).toBe(true);
    expect(store.lists().getIn(['reactions', 'items']).isEmpty()).toBe(true);
    expect(store.dispatch.mock.calls.some(([action]) => action.type === REACTED_STATUSES_EXPAND_FAIL)).toBe(false);
    current.resolve(response('current', '/current-next'));
    await flushResponses();

    expect(store.lists().getIn(['reactions', 'items']).toArray()).toEqual(['current']);
    expect(store.lists().getIn(['reactions', 'next'])).toBe('/current-next');
  });

  it('uses the selected filter on reentry and follows its pagination URL', async () => {
    apiGet.mockResolvedValueOnce(response('first', '/filtered-next')).mockResolvedValueOnce(response('second'));
    const store = makeStore();
    store.dispatch({ type: REACTION_FILTER_SET, name: '🔥' });

    store.dispatch(fetchReactedStatuses());
    await flushResponses();
    store.dispatch(expandReactedStatuses());
    await flushResponses();

    expect(apiGet.mock.calls).toEqual([
      ['/api/v1/reactions', { params: { name: '🔥' } }],
      ['/filtered-next'],
    ]);
    expect(store.lists().getIn(['reactions', 'items']).toArray()).toEqual(['first', 'second']);
    expect(store.lists().getIn(['reactions', 'next'])).toBeNull();
  });

  it('preserves the new list and cursor when an old page arrives after the new filter has loaded', async () => {
    apiGet.mockResolvedValueOnce(response('old-first', '/old-next'));
    const oldPage = deferred();
    apiGet.mockReturnValueOnce(oldPage.promise).mockResolvedValueOnce(response('current', '/current-next'));
    const store = makeStore();
    store.dispatch(fetchReactedStatuses());
    await flushResponses();

    store.dispatch(expandReactedStatuses());
    store.dispatch(setReactionFilter('🔥'));
    await flushResponses();
    oldPage.resolve(response('old-page', '/old-more'));
    await flushResponses();

    expect(store.lists().getIn(['reactions', 'items']).toArray()).toEqual(['current']);
    expect(store.lists().getIn(['reactions', 'next'])).toBe('/current-next');
    expect(importFetchedStatuses.mock.calls).toEqual([[response('old-first').data], [response('current').data]]);
  });

  it('clears old results and pagination when the newly selected filter fails', async () => {
    apiGet.mockResolvedValueOnce(response('old', '/old-next')).mockRejectedValueOnce(new Error('Current request failed'));
    const store = makeStore();
    store.dispatch(fetchReactedStatuses());
    await flushResponses();

    store.dispatch(setReactionFilter('🔥'));
    await flushResponses();

    expect(store.lists().getIn(['reactions', 'isLoading'])).toBe(false);
    expect(store.lists().getIn(['reactions', 'items']).isEmpty()).toBe(true);
    expect(store.lists().getIn(['reactions', 'next'])).toBeNull();
    store.dispatch(expandReactedStatuses());
    expect(apiGet).toHaveBeenCalledTimes(2);
  });

  it('does not duplicate an active request for the same filter or page', async () => {
    const first = deferred();
    const next = deferred();
    apiGet.mockReturnValueOnce(first.promise).mockReturnValueOnce(next.promise);
    const store = makeStore();

    store.dispatch(fetchReactedStatuses());
    store.dispatch(fetchReactedStatuses());
    expect(apiGet).toHaveBeenCalledTimes(1);
    first.resolve(response('first', '/next'));
    await flushResponses();

    store.dispatch(expandReactedStatuses());
    store.dispatch(expandReactedStatuses());
    expect(apiGet).toHaveBeenCalledTimes(2);
    next.resolve(response('second'));
    await flushResponses();
  });
});
