import type { UnknownAction } from '@reduxjs/toolkit';

import api, { getLinks } from 'flavours/glitch/api';

import timelinesReducer from '../reducers/timelines';

import { expandClipTimeline } from './timelines';
import { parseTimelineKey, timelineKey } from './timelines_typed';

vi.mock('flavours/glitch/api', () => ({
  default: vi.fn(),
  getLinks: vi.fn(),
}));

const apiGet = vi.fn();

const response = { data: [], status: 200 };

const initialState = timelinesReducer(undefined, { type: '@@INIT' });

const dispatchTimeline = async (
  action: ReturnType<typeof expandClipTimeline>,
  initialTimelineState = initialState,
) => {
  let state = initialTimelineState;

  const dispatch = vi.fn((dispatchedAction: unknown) => {
    if (typeof dispatchedAction !== 'function') {
      state = timelinesReducer(state, dispatchedAction as UnknownAction);
    }

    return dispatchedAction;
  });

  await action(
    dispatch,
    () =>
      ({
        getIn: (path: string[], defaultValue?: unknown) =>
          state.getIn(path.slice(1), defaultValue),
      }) as never,
  );

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
