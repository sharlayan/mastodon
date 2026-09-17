import type { UnknownAction } from '@reduxjs/toolkit';

import api, { getLinks } from 'flavours/glitch/api';

import timelinesReducer from '../reducers/timelines';

import {
  expandClipTimeline,
  expandHomeTimeline,
  expandHomeTimelineIfCurrent,
  homeTimelineMaxIdAt,
  jumpToHomeTimeline,
  returnToHomeTimelinePresent,
  updateTimeline,
} from './timelines';
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

describe('homeTimelineMaxIdAt', () => {
  beforeEach(() => {
    apiGet.mockReset();
    apiGet.mockResolvedValue(response);
    vi.mocked(api).mockReturnValue({ get: apiGet } as never);
    vi.mocked(getLinks).mockReset();
    vi.mocked(getLinks).mockReturnValue({ refs: [] } as never);
  });

  test('returns the first snowflake ID at the selected second', () => {
    expect(homeTimelineMaxIdAt(new Date('2026-09-14T12:34:56.789Z'))).toBe(
      '117269416902656000',
    );
  });

  test('keeps the time-machine mode through the request and response, then clears it', () => {
    const requestedState = timelinesReducer(initialState, {
      type: 'TIMELINE_EXPAND_REQUEST',
      timeline: 'home',
      timeMachine: true,
    });
    const loadedState = timelinesReducer(requestedState, {
      type: 'TIMELINE_EXPAND_SUCCESS',
      timeline: 'home',
      statuses: [{ id: 'historical-status' }],
      next: null,
      partial: false,
      isLoadingRecent: false,
      usePendingItems: false,
      timeMachine: true,
    });
    const clearedState = timelinesReducer(loadedState, {
      type: 'TIMELINE_CLEAR',
      timeline: 'home',
    });

    expect(requestedState.getIn(['home', 'isTimeMachine'])).toBe(true);
    expect(loadedState.getIn(['home', 'isTimeMachine'])).toBe(true);
    expect(clearedState.getIn(['home', 'isTimeMachine'])).toBe(false);
  });

  test('does not insert streaming updates while the time machine is active', () => {
    const timeMachineState = timelinesReducer(initialState, {
      type: 'TIMELINE_EXPAND_REQUEST',
      timeline: 'home',
      timeMachine: true,
    });
    const reducerState = timelinesReducer(timeMachineState, {
      type: 'TIMELINE_UPDATE',
      timeline: 'home',
      status: { id: 'new-status' },
      usePendingItems: false,
      filtered: false,
    });
    const dispatch = vi.fn();
    const getState = () => ({
      getIn: (path: string[]) => timeMachineState.getIn(path.slice(1)),
    });

    updateTimeline('home', { id: 'new-status' })(dispatch, getState);

    expect(reducerState).toBe(timeMachineState);
    expect(dispatch).not.toHaveBeenCalled();
  });

  test('does not refresh the current home timeline while the time machine is active', () => {
    const timeMachineState = timelinesReducer(initialState, {
      type: 'TIMELINE_EXPAND_REQUEST',
      timeline: 'home',
      timeMachine: true,
    });
    const dispatch = vi.fn();

    expandHomeTimelineIfCurrent()(dispatch, () => ({
      getIn: (path: string[]) => timeMachineState.getIn(path.slice(1)),
    }));

    expect(dispatch).not.toHaveBeenCalled();
  });

  test('tracks the next link for an empty time-machine page', async () => {
    const nextUri =
      'https://example.test/api/v1/timelines/home?max_id=older-candidate';
    vi.mocked(getLinks).mockReturnValue({
      refs: [{ rel: 'next', uri: nextUri }],
    } as never);

    const { state } = await dispatchTimeline(
      expandHomeTimeline({ maxId: '200', timeMachine: true }),
    );

    expect(state.getIn(['home', 'next'])).toBe(nextUri);
    expect(state.getIn(['home', 'hasMore'])).toBe(true);
  });

  test('clears the current timeline before requesting the selected time', async () => {
    const actions: unknown[] = [];
    type TimelineThunk = (
      dispatch: (action: unknown) => unknown,
      getState: () => typeof initialState,
    ) => unknown;
    const dispatch = (action: unknown): unknown => {
      actions.push(action);

      if (typeof action === 'function') {
        return (action as TimelineThunk)(dispatch, () => initialState);
      }

      return action;
    };

    await jumpToHomeTimeline(new Date('2026-09-14T12:34:56.789Z'))(dispatch);

    const actionIndex = (type: string) =>
      actions.findIndex(
        (action) =>
          typeof action === 'object' &&
          action !== null &&
          'type' in action &&
          action.type === type,
      );
    const clearIndex = actionIndex('TIMELINE_CLEAR');
    const requestIndex = actionIndex('TIMELINE_EXPAND_REQUEST');

    expect(clearIndex).toBeGreaterThanOrEqual(0);
    expect(requestIndex).toBeGreaterThan(clearIndex);
    expect(apiGet).toHaveBeenCalledWith('/api/v1/timelines/home', {
      params: { max_id: '117269416902656000' },
    });
    expect(actions).toContainEqual(
      expect.objectContaining({
        type: 'TIMELINE_EXPAND_REQUEST',
        timeMachine: true,
      }),
    );
  });

  test('discards an older time-machine response after another jump', async () => {
    interface ApiResponse {
      data: { id: string }[];
      status: number;
    }
    const pendingResponses: ((response: ApiResponse) => void)[] = [];
    apiGet.mockImplementation(
      () =>
        new Promise<ApiResponse>((resolve) => {
          pendingResponses.push(resolve);
        }),
    );

    let state: typeof initialState = initialState;
    type TimelineThunk = (
      dispatch: (action: unknown) => unknown,
      getState: () => typeof initialState,
    ) => unknown;
    const dispatch = (action: unknown): unknown => {
      if (typeof action === 'function') {
        return (action as TimelineThunk)(
          dispatch,
          () =>
            ({
              getIn: (path: string[], defaultValue?: unknown) =>
                state.getIn(path.slice(1), defaultValue),
            }) as never,
        );
      }

      state = timelinesReducer(state, action as UnknownAction);
      return action;
    };

    const firstJump = jumpToHomeTimeline(new Date('2026-09-14T12:00:00Z'))(
      dispatch,
    ) as Promise<unknown>;
    const secondJump = jumpToHomeTimeline(new Date('2026-09-14T11:00:00Z'))(
      dispatch,
    ) as Promise<unknown>;

    const activeRequestId = state.getIn(['home', 'requestId']);

    pendingResponses[0]?.({ data: [], status: 200 });
    await firstJump;
    expect(state.getIn(['home', 'requestId'])).toBe(activeRequestId);
    expect(state.getIn(['home', 'isLoading'])).toBe(true);

    pendingResponses[1]?.({ data: [], status: 200 });
    await secondJump;
    expect(state.getIn(['home', 'requestId'])).toBeNull();
    expect(state.getIn(['home', 'isLoading'])).toBe(false);
  });

  test('keeps updates blocked until returning to the present succeeds', async () => {
    let state: typeof initialState = timelinesReducer(initialState, {
      type: 'TIMELINE_EXPAND_REQUEST',
      timeline: 'home',
      timeMachine: true,
    });
    type TimelineThunk = (
      dispatch: (action: unknown) => unknown,
      getState: () => typeof initialState,
    ) => unknown;
    const dispatch = (action: unknown): unknown => {
      if (typeof action === 'function') {
        return (action as TimelineThunk)(
          dispatch,
          () =>
            ({
              getIn: (path: string[], defaultValue?: unknown) =>
                state.getIn(path.slice(1), defaultValue),
            }) as never,
        );
      }

      state = timelinesReducer(state, action as UnknownAction);
      return action;
    };

    const request = returnToHomeTimelinePresent()(dispatch) as Promise<unknown>;

    expect(state.getIn(['home', 'isTimeMachine'])).toBe(true);
    await request;
    expect(apiGet).toHaveBeenCalledWith('/api/v1/timelines/home', {
      params: {},
    });
    expect(state.getIn(['home', 'isTimeMachine'])).toBe(false);
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
