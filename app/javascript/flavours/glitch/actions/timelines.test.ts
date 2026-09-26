import type { UnknownAction } from '@reduxjs/toolkit';

import api, { getLinks } from 'flavours/glitch/api';

import timelinesReducer from '../reducers/timelines';

import {
  expandClipTimeline,
  expandHomeTimeline,
  fillHomeTimelineGaps,
} from './timelines';
import { parseTimelineKey, timelineKey } from './timelines_typed';

vi.mock('flavours/glitch/api', () => ({
  default: vi.fn(),
  getLinks: vi.fn(),
}));

vi.mock('./importer', () => ({
  importFetchedStatus: vi.fn(() => ({ type: 'TEST_IMPORT_STATUS' })),
  importFetchedStatuses: vi.fn(() => ({ type: 'TEST_IMPORT_STATUSES' })),
}));

const apiGet = vi.fn();

const response = { data: [], status: 200 };

const initialState = timelinesReducer(undefined, { type: '@@INIT' });

const dispatchTimeline = async (
  action:
    | ReturnType<typeof expandClipTimeline>
    | ReturnType<typeof fillHomeTimelineGaps>,
  initialTimelineState = initialState,
) => {
  let state = initialTimelineState;

  const dispatch = vi.fn((dispatchedAction: unknown) => {
    if (typeof dispatchedAction === 'function') {
      return (dispatchedAction as typeof action)(dispatch, getState);
    }

    state = timelinesReducer(state, dispatchedAction as UnknownAction);
    return dispatchedAction;
  });

  const getState = () =>
    ({
      getIn: (path: string[], defaultValue?: unknown) =>
        state.getIn(path.slice(1), defaultValue),
    }) as never;

  await action(dispatch, getState);

  return { dispatch, state };
};

describe('expandClipTimeline', () => {
  beforeEach(() => {
    apiGet.mockReset();
    apiGet.mockResolvedValue(response);
    vi.mocked(api).mockReturnValue({ get: apiGet } as never);
    vi.mocked(getLinks).mockReset();
  });

  test('uses the next Link URI instead of the rendered status ID', async () => {
    const nextUri =
      'https://example.test/api/v1/clips/clip-id/statuses?max_id=clip-status-id';
    vi.mocked(getLinks).mockReturnValue({
      refs: [{ rel: 'next', uri: nextUri }],
    } as never);

    const { dispatch, state } = await dispatchTimeline(
      expandClipTimeline('clip-id', { nextUri }),
    );

    expect(apiGet).toHaveBeenCalledWith(nextUri, { params: {} });
    expect(dispatch).toHaveBeenCalledWith(
      expect.objectContaining({
        type: 'TIMELINE_EXPAND_REQUEST',
        skipLoading: false,
      }),
    );
    expect(state.getIn(['clip:clip-id', 'next'])).toBe(nextUri);
  });

  test('does not derive a refresh cursor from status IDs and stops with no next Link', async () => {
    vi.mocked(getLinks).mockReturnValue({ refs: [] } as never);
    const stateWithStatus = timelinesReducer(initialState, {
      type: 'TIMELINE_EXPAND_SUCCESS',
      timeline: 'clip:clip-id',
      statuses: [{ id: 'status-id' }],
      next: null,
      partial: false,
      isLoadingRecent: false,
      usePendingItems: false,
    });

    const { state } = await dispatchTimeline(
      expandClipTimeline('clip-id'),
      stateWithStatus,
    );

    expect(apiGet).toHaveBeenCalledWith('/api/v1/clips/clip-id/statuses', {
      params: {},
    });
    expect(state.getIn(['clip:clip-id', 'next'])).toBeNull();
    expect(state.getIn(['clip:clip-id', 'hasMore'])).toBe(false);
  });
});

describe('fillHomeTimelineGaps', () => {
  beforeEach(() => {
    apiGet.mockReset();
    apiGet.mockResolvedValue(response);
    vi.mocked(api).mockReturnValue({ get: apiGet } as never);
    vi.mocked(getLinks).mockReturnValue({ refs: [] } as never);
  });

  test('requests the actual gap boundary with max_id', async () => {
    const stateWithStatuses = timelinesReducer(initialState, {
      type: 'TIMELINE_EXPAND_SUCCESS',
      timeline: 'home',
      statuses: [{ id: '40' }, { id: '30' }, { id: '10' }],
      next: null,
      partial: false,
      isLoadingRecent: false,
      usePendingItems: false,
    });
    const stateWithGap = timelinesReducer(stateWithStatuses, {
      type: 'TIMELINE_INSERT',
      timeline: 'home',
      key: null,
      index: 2,
    });

    await dispatchTimeline(fillHomeTimelineGaps(), stateWithGap);

    expect(apiGet).toHaveBeenCalledTimes(1);
    expect(apiGet).toHaveBeenCalledWith('/api/v1/timelines/home', {
      params: { max_id: '30' },
    });
  });

  test('loads the latest page and clears a leading gap when the old status overlaps', async () => {
    const stateWithStatus = timelinesReducer(initialState, {
      type: 'TIMELINE_EXPAND_SUCCESS',
      timeline: 'home',
      statuses: [{ id: '10' }],
      next: null,
      partial: false,
      isLoadingRecent: false,
      usePendingItems: false,
    });
    const reconnectedState = timelinesReducer(stateWithStatus, {
      type: 'TIMELINE_CONNECT',
      timeline: 'home',
      usePendingItems: false,
    });

    expect(reconnectedState.getIn(['home', 'items', 0])).toBeNull();

    apiGet.mockResolvedValue({ data: [{ id: '10' }], status: 200 });

    const { state } = await dispatchTimeline(
      fillHomeTimelineGaps(),
      reconnectedState,
    );
    expect(apiGet).toHaveBeenCalledWith('/api/v1/timelines/home', {
      params: {},
    });
    expect(state.getIn(['home', 'items', 0])).toBe('10');

    apiGet.mockClear();
    await dispatchTimeline(
      expandHomeTimeline({ maxId: null }),
      reconnectedState,
    );
    expect(apiGet).toHaveBeenCalledWith('/api/v1/timelines/home', {
      params: { max_id: null },
    });
  });
});

describe('timelineKey', () => {
  test('returns expected key for account timeline with filters', () => {
    const key = timelineKey({
      type: 'account',
      userId: '123',
      replies: true,
      boosts: false,
      media: true,
    });
    expect(key).toBe('account:123:0110');
  });

  test('returns expected key for account timeline with tag', () => {
    const key = timelineKey({
      type: 'account',
      userId: '456',
      tagged: 'nature',
      replies: true,
    });
    expect(key).toBe('account:456:0100:nature');
  });

  test('returns expected key for account timeline with pins', () => {
    const key = timelineKey({
      type: 'account',
      userId: '789',
      pinned: true,
    });
    expect(key).toBe('account:789:0001');
  });
});

describe('parseTimelineKey', () => {
  test('parses account timeline key with filters correctly', () => {
    const params = parseTimelineKey('account:123:1010');
    expect(params).toEqual({
      type: 'account',
      userId: '123',
      boosts: true,
      replies: false,
      media: true,
      pinned: false,
    });
  });

  test('parses account timeline key with tag correctly', () => {
    const params = parseTimelineKey('account:456:0100:nature');
    expect(params).toEqual({
      type: 'account',
      userId: '456',
      replies: true,
      boosts: false,
      media: false,
      pinned: false,
      tagged: 'nature',
    });
  });

  test('parses legacy account timeline key with pinned correctly', () => {
    const params = parseTimelineKey('account:789:pinned:nature');
    expect(params).toEqual({
      type: 'account',
      userId: '789',
      replies: false,
      boosts: false,
      media: false,
      pinned: true,
      tagged: 'nature',
    });
  });

  test('parses legacy account timeline key with media correctly', () => {
    const params = parseTimelineKey('account:789:media');
    expect(params).toEqual({
      type: 'account',
      userId: '789',
      replies: false,
      boosts: false,
      media: true,
      pinned: false,
    });
  });
});
