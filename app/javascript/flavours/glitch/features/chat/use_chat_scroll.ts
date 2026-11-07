import type { RefObject } from 'react';
import {
  useEffect,
  useEffectEvent,
  useLayoutEffect,
  useSyncExternalStore,
} from 'react';

import type {
  Box,
  Command,
  LayoutReading,
  ScrollEvent,
  Snapshot,
  TimerName,
  ViewportReading,
} from './scroll_control';
import {
  distanceFromNewest,
  initialScrollState,
  rectShown,
  rectVisible,
  revealAmount,
  step,
  visibleArea,
} from './scroll_control';

// The page itself, measured and moved for scroll_control.ts. Nothing here decides where to scroll or whether to
// follow the newest message: it reports what happened and carries out what `step` says.

export const usesTouchKeyboard = () =>
  typeof window.matchMedia === 'function' &&
  window.matchMedia('(pointer: coarse)').matches;

// The box the room scrolls in: its own column, or the page.
const chatScrollport = (end: HTMLElement): Element | null => {
  let parent = end.parentElement;
  while (
    parent &&
    parent !== document.body &&
    parent !== document.documentElement
  ) {
    const overflow = window.getComputedStyle(parent).overflowY;
    if (
      (overflow === 'auto' || overflow === 'scroll') &&
      parent.scrollHeight > parent.clientHeight
    ) {
      return parent;
    }
    parent = parent.parentElement;
  }
  return document.scrollingElement;
};

const box = (rect: DOMRect): Box => ({ top: rect.top, bottom: rect.bottom });

const readViewport = (): ViewportReading => {
  const visual = window.visualViewport;
  return {
    innerHeight: window.innerHeight,
    rootClientHeight: document.documentElement.clientHeight,
    scrollY: window.scrollY,
    visual: visual
      ? {
          height: visual.height,
          offsetTop: visual.offsetTop,
          scale: visual.scale,
          pageTop: visual.pageTop,
        }
      : null,
  };
};

const currentScale = () => visibleArea(readViewport()).scale;
const viewportHeight = () =>
  window.visualViewport?.height ?? window.innerHeight;

interface Room {
  end: HTMLElement;
  list: HTMLElement;
  composer: HTMLElement | null;
}

const readLayout = (room: Room): LayoutReading => {
  const scroller = chatScrollport(room.end);
  const navigation = document
    .querySelector('.ui__navigation-bar')
    ?.getBoundingClientRect();
  return {
    viewport: readViewport(),
    scroller:
      scroller && scroller !== document.scrollingElement
        ? box(scroller.getBoundingClientRect())
        : null,
    navigation: navigation
      ? {
          top: navigation.top,
          bottom: navigation.bottom,
          height: navigation.height,
        }
      : null,
    composer: room.composer ? box(room.composer.getBoundingClientRect()) : null,
    end: box(room.end.getBoundingClientRect()),
  };
};

const composerFocused = (composer: HTMLElement | null) => {
  const active = document.activeElement;
  return (
    usesTouchKeyboard() &&
    active instanceof HTMLTextAreaElement &&
    Boolean(composer?.contains(active))
  );
};

const firstMessageOf = (room: Room) =>
  room.list.querySelector<HTMLElement>('[id^="chat-message-"]');

// Measured only when a decision reads it, once per happening.
const snapshotOf = (room: Room): Snapshot => {
  let layout: LayoutReading | undefined;
  const measured = () => (layout ??= readLayout(room));
  return {
    get viewport() {
      return readViewport();
    },
    get ownScroller() {
      const scroller = chatScrollport(room.end);
      return Boolean(scroller && scroller !== document.scrollingElement);
    },
    get firstMessage() {
      const first = firstMessageOf(room);
      return first
        ? {
            id: first.id.slice('chat-message-'.length),
            top: first.getBoundingClientRect().top,
          }
        : null;
    },
    messageTop: (id: string) => {
      const message = document.getElementById(`chat-message-${id}`);
      return message && room.list.contains(message)
        ? message.getBoundingClientRect().top
        : null;
    },
    messageShown: (id: string) => {
      const message = document.getElementById(`chat-message-${id}`);
      return Boolean(
        message &&
        room.list.contains(message) &&
        rectShown(measured(), box(message.getBoundingClientRect())),
      );
    },
    get scale() {
      return currentScale();
    },
    get height() {
      return viewportHeight();
    },
    get composerFocused() {
      return composerFocused(room.composer);
    },
    get scrollTop() {
      return chatScrollport(room.end)?.scrollTop ?? 0;
    },
    get distance() {
      return distanceFromNewest(measured());
    },
    get reveal() {
      const scroller = chatScrollport(room.end);
      const last = Array.from(
        room.list.querySelectorAll<HTMLElement>('[id^="chat-message-"]'),
      ).at(-1);
      if (!scroller || !last) return 0;
      const height =
        scroller === document.scrollingElement
          ? window.innerHeight
          : scroller.clientHeight;
      return revealAmount({
        last: box(last.getBoundingClientRect()),
        composer: measured().composer,
        remaining: scroller.scrollHeight - height - scroller.scrollTop,
      });
    },
  };
};

const detachedSnapshot = (): Snapshot => ({
  scale: currentScale(),
  height: viewportHeight(),
  composerFocused: false,
  scrollTop: 0,
  distance: Number.POSITIVE_INFINITY,
  reveal: 0,
  viewport: readViewport(),
  ownScroller: false,
  firstMessage: null,
  messageTop: () => null,
  messageShown: () => false,
});

// Raises the composer and the navigation bar onto the visible bottom while the keyboard is open, and puts back what
// was there before.
const createLift = (room: Room) => {
  let applied: {
    navigation: HTMLElement | null;
    bottom: string;
    bottomPriority: string;
    lift: string;
    liftPriority: string;
  } | null = null;

  const restore = () => {
    if (!applied) return;
    const { navigation, bottom, bottomPriority, lift, liftPriority } = applied;
    applied = null;
    if (navigation) {
      if (bottom)
        navigation.style.setProperty('bottom', bottom, bottomPriority);
      else navigation.style.removeProperty('bottom');
    }
    if (room.composer) {
      if (lift)
        room.composer.style.setProperty(
          '--chat-keyboard-lift',
          lift,
          liftPriority,
        );
      else room.composer.style.removeProperty('--chat-keyboard-lift');
    }
  };

  const apply = (by: number) => {
    if (!applied) {
      const navigation = document.querySelector<HTMLElement>(
        '.ui__navigation-bar',
      );
      applied = {
        navigation,
        bottom: navigation?.style.getPropertyValue('bottom') ?? '',
        bottomPriority: navigation?.style.getPropertyPriority('bottom') ?? '',
        lift:
          room.composer?.style.getPropertyValue('--chat-keyboard-lift') ?? '',
        liftPriority:
          room.composer?.style.getPropertyPriority('--chat-keyboard-lift') ??
          '',
      };
    }
    const value = `${by}px`;
    applied.navigation?.style.setProperty('bottom', value);
    room.composer?.style.setProperty('--chat-keyboard-lift', value);
  };

  return { apply, restore };
};

// Holds the room's scroll state and runs it, one happening at a time.
export const createChatScroll = (initialTarget: string | null) => {
  let state = initialScrollState(initialTarget);
  let room: Room | null = null;
  let execute: ((command: Command) => void) | null = null;
  const timers = new Map<TimerName, number>();
  const listeners = new Set<() => void>();
  const queue: ScrollEvent[] = [];
  let running = false;

  const clearTimer = (name: TimerName) => {
    const timer = timers.get(name);
    if (timer === undefined) return;
    window.clearTimeout(timer);
    timers.delete(name);
  };

  // What `step` says is done in order; a happening it causes waits for the one before to be done.
  const dispatch = (event: ScrollEvent) => {
    queue.push(event);
    if (running) return;
    running = true;
    try {
      for (let next = queue.shift(); next; next = queue.shift()) {
        const target = state.target?.id ?? null;
        const result = step(
          state,
          next,
          room ? snapshotOf(room) : detachedSnapshot(),
        );
        state = result.state;
        for (const command of result.commands) {
          if (command.type === 'timer') {
            const { name, delay } = command;
            clearTimer(name);
            timers.set(
              name,
              window.setTimeout(() => {
                timers.delete(name);
                dispatch({ type: 'timer', name });
              }, delay),
            );
          } else if (command.type === 'clearTimer') {
            clearTimer(command.name);
          } else {
            execute?.(command);
          }
        }
        if ((state.target?.id ?? null) !== target)
          listeners.forEach((listener) => {
            listener();
          });
      }
    } finally {
      running = false;
    }
  };

  return {
    dispatch,
    following: () => state.following,
    // Following, and not zoomed in: what comes in is shown and can be read.
    follows: () => state.following && currentScale() === 1,
    seeking: () => state.target?.phase === 'seeking',
    targetId: () => state.target?.id ?? null,
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    // Whether a message is actually on the screen, clear of the composer, in a page that is shown.
    messageVisible: (id: string) => {
      if (!room || document.visibilityState === 'hidden') return false;
      const message = document.getElementById(`chat-message-${id}`);
      if (!message || !room.list.contains(message)) return false;
      return rectVisible(
        readLayout(room),
        box(message.getBoundingClientRect()),
      );
    },
    attach: (attached: Room, run: (command: Command) => void) => {
      room = attached;
      execute = run;
    },
    detach: () => {
      room = null;
      execute = null;
    },
    stop: () => {
      timers.forEach((timer) => {
        window.clearTimeout(timer);
      });
      timers.clear();
    },
  };
};

export type ChatScroll = ReturnType<typeof createChatScroll>;

interface JumpButton {
  update: (next: { away?: boolean }) => void;
}

// Connects a room on the page to its scroll state: what the reader and the page do goes in as happenings, and what
// comes back is done to the page.
export const useChatScroll = (
  scroll: ChatScroll,
  {
    endRef,
    listRef,
    composerRef,
    jumpButton,
    attachKey,
    screen,
    newestId,
    newestIsMine,
    oldestId,
    targetShown,
    onReadCheck,
    onReturn,
    onReadNewest,
    onForgetSearch,
  }: {
    endRef: RefObject<HTMLElement | null>;
    listRef: RefObject<HTMLElement | null>;
    composerRef: RefObject<HTMLElement | null>;
    jumpButton: JumpButton;
    // Changes whenever the room's elements may have been replaced.
    attachKey: string;
    // The room and view the newest message is shown in, when it is this room's.
    screen: string | null;
    newestId: string | undefined;
    newestIsMine: boolean;
    // The oldest message shown: older ones came in when it changes.
    oldestId: string | undefined;
    // The message being gone to is among those shown.
    targetShown: boolean;
    onReadCheck: () => void;
    onReturn: () => void;
    onReadNewest: () => void;
    // The page's history entry is no longer to open the room at the searched message.
    onForgetSearch: () => void;
  },
) => {
  const read = useEffectEvent((kind: 'check' | 'return' | 'newest') => {
    if (kind === 'newest') {
      onReadNewest();
      return;
    }
    if (kind === 'return') onReturn();
    onReadCheck();
  });
  const forgetSearch = useEffectEvent(() => {
    onForgetSearch();
  });

  // Before the screen is drawn, so that what is aligned is never seen out of place.
  useLayoutEffect(() => {
    const end = endRef.current;
    const list = listRef.current;
    if (!end || !list) return undefined;
    const composer = composerRef.current;
    const room: Room = { end, list, composer };
    const lift = createLift(room);

    scroll.attach(room, (command) => {
      switch (command.type) {
        case 'alignEnd': {
          if (typeof end.scrollIntoView === 'function')
            end.scrollIntoView({ block: 'end' });
          // A sticky composer can leave the end in view before the box reaches its bottom.
          const scroller = chatScrollport(end);
          if (scroller) scroller.scrollTop = scroller.scrollHeight;
          break;
        }
        case 'reveal':
        case 'scrollBy': {
          const scroller = chatScrollport(end);
          if (scroller) scroller.scrollTop += command.by;
          break;
        }
        case 'scrollToMessage': {
          const target = document.getElementById(`chat-message-${command.id}`);
          const scroller = chatScrollport(end);
          const before = scroller?.scrollTop;
          if (typeof target?.scrollIntoView === 'function')
            target.scrollIntoView({ block: 'center' });
          const after = scroller?.scrollTop;
          scroll.dispatch({
            type: 'targetScrolled',
            id: command.id,
            movedUp:
              before !== undefined && after !== undefined && after < before - 1,
            moved:
              before !== undefined &&
              after !== undefined &&
              Math.abs(after - before) > 1,
          });
          break;
        }
        case 'restoreScroll': {
          const scroller = chatScrollport(end);
          if (scroller) scroller.scrollTop = command.top;
          break;
        }
        case 'away':
          jumpButton.update({ away: command.value });
          break;
        case 'read':
          read(command.kind);
          break;
        case 'forgetSearch':
          forgetSearch();
          break;
        case 'lift':
          if (command.by === null) lift.restore();
          else lift.apply(command.by);
          break;
      }
    });
    scroll.dispatch({ type: 'attached' });

    const inComposer = (event: Event) =>
      event.target instanceof Node && Boolean(composer?.contains(event.target));
    const onScroll = (event: Event) => {
      if (!inComposer(event)) scroll.dispatch({ type: 'scrolled' });
    };
    const onScrollEnd = (event: Event) => {
      if (!inComposer(event)) scroll.dispatch({ type: 'scrollEnded' });
    };
    const onTouchMove = (event: Event) => {
      if (!inComposer(event))
        scroll.dispatch({ type: 'userIntent', touch: true });
    };
    const onWheel = (event: Event) => {
      if (!inComposer(event))
        scroll.dispatch({ type: 'userIntent', touch: false });
    };
    const onTouchStart = (event: Event) => {
      if (!inComposer(event)) scroll.dispatch({ type: 'touch', down: true });
    };
    // A finger still on the screen moves again and says so.
    const onTouchEnd = () => {
      scroll.dispatch({ type: 'touch', down: false });
    };
    const onFocusIn = (event: FocusEvent) => {
      if (usesTouchKeyboard() && event.target instanceof HTMLTextAreaElement)
        scroll.dispatch({ type: 'composerFocused' });
    };
    const onFocusOut = () => {
      scroll.dispatch({ type: 'composerBlurred' });
    };
    const onPointerDown = (event: Event) => {
      if (
        event.target instanceof Element &&
        !composer?.contains(event.target) &&
        event.target.closest('button, a')
      )
        scroll.dispatch({ type: 'pageAction' });
    };
    const onResize = () => {
      scroll.dispatch({ type: 'viewportResized' });
    };
    const onViewportScroll = () => {
      scroll.dispatch({ type: 'viewportScrolled' });
    };

    window.addEventListener('scroll', onScroll, {
      capture: true,
      passive: true,
    });
    window.addEventListener('scrollend', onScrollEnd, { capture: true });
    composer?.addEventListener('focusin', onFocusIn);
    composer?.addEventListener('focusout', onFocusOut);
    window.addEventListener('touchstart', onTouchStart, { passive: true });
    window.addEventListener('touchmove', onTouchMove, { passive: true });
    window.addEventListener('touchend', onTouchEnd, { passive: true });
    window.addEventListener('touchcancel', onTouchEnd, { passive: true });
    window.addEventListener('wheel', onWheel, { passive: true });
    window.addEventListener('pointerdown', onPointerDown, { passive: true });
    window.addEventListener('resize', onResize);
    window.visualViewport?.addEventListener('resize', onResize);
    window.visualViewport?.addEventListener('scroll', onViewportScroll);
    const observer =
      typeof ResizeObserver === 'function'
        ? new ResizeObserver(() => {
            scroll.dispatch({ type: 'contentResized' });
          })
        : null;
    observer?.observe(list);
    if (composer) observer?.observe(composer);

    return () => {
      window.removeEventListener('scroll', onScroll, { capture: true });
      window.removeEventListener('scrollend', onScrollEnd, { capture: true });
      composer?.removeEventListener('focusin', onFocusIn);
      composer?.removeEventListener('focusout', onFocusOut);
      window.removeEventListener('touchstart', onTouchStart);
      window.removeEventListener('touchmove', onTouchMove);
      window.removeEventListener('touchend', onTouchEnd);
      window.removeEventListener('touchcancel', onTouchEnd);
      window.removeEventListener('wheel', onWheel);
      window.removeEventListener('pointerdown', onPointerDown);
      window.removeEventListener('resize', onResize);
      window.visualViewport?.removeEventListener('resize', onResize);
      window.visualViewport?.removeEventListener('scroll', onViewportScroll);
      observer?.disconnect();
      scroll.dispatch({ type: 'detached' });
      scroll.detach();
      lift.restore();
    };
  }, [attachKey, composerRef, endRef, jumpButton, listRef, scroll]);

  useLayoutEffect(() => {
    if (!screen || !newestId) return;
    scroll.dispatch({ type: 'newestShown', screen, mine: newestIsMine });
  }, [newestId, newestIsMine, screen, scroll]);

  // After older messages are drawn above and before the screen shows them, so the reader's place is kept.
  useLayoutEffect(() => {
    scroll.dispatch({ type: 'olderLoaded' });
  }, [oldestId, scroll]);

  const targetId = useSyncExternalStore(scroll.subscribe, scroll.targetId);
  useLayoutEffect(() => {
    if (targetId && targetShown)
      scroll.dispatch({ type: 'targetLoaded', id: targetId });
  }, [scroll, targetId, targetShown]);

  useEffect(
    () => () => {
      scroll.stop();
    },
    [scroll],
  );
};
