import { fromJS } from 'immutable';

import { act, renderHook } from '@testing-library/react';
import { vi } from 'vitest';

import { hideStatus } from '@/flavours/glitch/actions/statuses';
import type { ExpandedStatusShape } from '@/flavours/glitch/models/status';
import { useAppSelector } from '@/flavours/glitch/store';
import type { RootState } from '@/flavours/glitch/store';

import { shouldAutoCollapseStatus, usePostCollapse } from './collapse';

const dispatch = vi.hoisted(() => vi.fn());

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppSelector: vi.fn(),
  useAppDispatch: () => dispatch,
}));

const status = {
  id: '1',
  contentHtml: '<p>🌸🌸🌸🌸</p>',
  media_attachments: [],
  spoiler_text: '',
} as unknown as ExpandedStatusShape;

describe('redesign automatic post collapse', () => {
  const shouldCollapse = (settings = {}, overrides = {}) =>
    shouldAutoCollapseStatus({
      status,
      settings: fromJS(settings),
      contentHeight: 0,
      boosted: false,
      ...overrides,
    });

  it('counts Unicode characters without HTML tags', () => {
    expect(shouldCollapse({ lengthy: true, character_limit: '4' })).toBe(true);
    expect(shouldCollapse({ lengthy: true, character_limit: '5' })).toBe(false);
  });

  it('uses height only when a character limit is absent', () => {
    expect(
      shouldCollapse({ lengthy: true, height: 400 }, { contentHeight: 401 }),
    ).toBe(true);
    expect(
      shouldCollapse(
        { lengthy: true, height: 400, character_limit: '5' },
        { contentHeight: 900 },
      ),
    ).toBe(false);
  });

  it('allows extra height for feed media, but not notifications', () => {
    const overrides = {
      status: { ...status, media_attachments: [{}] },
      contentHeight: 500,
    };
    expect(shouldCollapse({ lengthy: true }, overrides)).toBe(false);
    expect(
      shouldCollapse(
        { lengthy: true },
        { ...overrides, contextType: 'notifications', unread: false },
      ),
    ).toBe(true);
  });

  it.each([true, undefined])(
    'does not auto-collapse notifications with unread=%s',
    (unread) => {
      expect(
        shouldCollapse({ all: true }, { contextType: 'notifications', unread }),
      ).toBe(false);
    },
  );

  it.each([
    [{ notifications: true }, { contextType: 'notifications', unread: false }],
    [{ reblogs: true }, { boosted: true }],
    [{ replies: true }, { status: { ...status, in_reply_to_id: '2' } }],
    [{ quotes: true }, { status: { ...status, quote: {} } }],
    [{ media: true }, { status: { ...status, media_attachments: [{}] } }],
  ])(
    'preserves the individual auto-collapse preferences',
    (settings, overrides) => {
      expect(shouldCollapse(settings, overrides)).toBe(true);
    },
  );

  it('keeps media inside a CW under the CW control', () => {
    expect(
      shouldCollapse(
        { media: true },
        { status: { ...status, media_attachments: [{}], spoiler_text: 'CW' } },
      ),
    ).toBe(false);
  });
});

describe('redesign manual post collapse', () => {
  function configure(
    collapsed = { enabled: true, auto: { all: true }, show_action_bar: false },
    sharedState = false,
  ) {
    vi.mocked(useAppSelector).mockImplementation((selector) =>
      selector({
        local_settings: fromJS({
          collapsed,
          content_warnings: { shared_state: sharedState },
        }),
      } as unknown as RootState),
    );
  }

  beforeEach(() => {
    configure();
  });

  const props = { status, boosted: false, disabled: false };

  it('preserves a manual expansion across measurement and status updates, and resets for another post', () => {
    const { result, rerender } = renderHook(usePostCollapse, {
      initialProps: props,
    });
    expect(result.current.isCollapsed).toBe(true);
    expect(result.current.showActionBar).toBe(false);
    act(() => {
      result.current.onToggle();
    });
    act(() => {
      result.current.onMeasure(900);
    });
    rerender({
      ...props,
      status: { ...status, contentHtml: '<p>Updated</p>' },
    });
    expect(result.current.isCollapsed).toBe(false);
    rerender({ ...props, status: { ...status, id: '2' } });
    expect(result.current.isCollapsed).toBe(true);
  });

  it('does not collapse quotes or detailed posts when disabled by their caller', () => {
    const { result } = renderHook(() =>
      usePostCollapse({ ...props, disabled: true }),
    );
    act(() => {
      result.current.onCollapsedChange(true);
    });
    expect(result.current.enabled).toBe(false);
    expect(result.current.isCollapsed).toBe(false);
  });

  it('respects an explicitly revealed shared CW', () => {
    configure(undefined, true);
    const { result } = renderHook(() =>
      usePostCollapse({
        ...props,
        status: { ...status, spoiler_text: 'CW', hidden: false },
      }),
    );
    expect(result.current.isCollapsed).toBe(false);
  });

  it('unfolds a manually collapsed post when its shared CW opens, including a forced collapsed prop', () => {
    configure(undefined, true);
    const initialProps = {
      ...props,
      collapsed: true,
      status: { ...status, spoiler_text: 'CW', hidden: true },
    };
    const { result, rerender } = renderHook(usePostCollapse, { initialProps });
    act(() => {
      result.current.onCollapsedChange(true);
    });
    expect(result.current.isCollapsed).toBe(true);
    rerender({
      ...initialProps,
      status: { ...initialProps.status, hidden: false },
    });
    expect(result.current.isCollapsed).toBe(false);
    rerender(initialProps);
    expect(result.current.isCollapsed).toBe(false);
  });

  it('closes a revealed shared CW when manually collapsing', () => {
    configure(undefined, true);
    const initialProps = {
      ...props,
      status: { ...status, spoiler_text: 'CW', hidden: false },
    };
    const { result, rerender } = renderHook(usePostCollapse, { initialProps });
    act(() => {
      result.current.onCollapsedChange(true);
    });
    expect(dispatch).toHaveBeenCalledWith(hideStatus(status.id));
    rerender({
      ...initialProps,
      status: { ...initialProps.status, hidden: true },
    });
    expect(result.current.isCollapsed).toBe(true);
  });

  it('applies a new collapsed prop after a manual choice', () => {
    const { result, rerender } = renderHook(usePostCollapse, {
      initialProps: { ...props, collapsed: false },
    });
    act(() => {
      result.current.onCollapsedChange(false);
    });
    rerender({ ...props, collapsed: true });
    expect(result.current.isCollapsed).toBe(true);
  });

  it('keeps collapse opt-in', () => {
    configure({ enabled: false, auto: { all: true }, show_action_bar: true });
    const { result } = renderHook(() => usePostCollapse(props));
    act(() => {
      result.current.onToggle();
    });
    expect(result.current.isCollapsed).toBe(false);
  });
});
