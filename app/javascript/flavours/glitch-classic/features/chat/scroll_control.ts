export const FOLLOW_NEWEST_DISTANCE = 240;
export const AT_NEWEST_TOLERANCE = 2;
export const HIGHLIGHT_DURATION_MS = 3000;
const OWN_JUMP_MS = 200;
const USER_SCROLL_SETTLE_MS = 200;
const KEYBOARD_BLUR_MS = 700;
const KEYBOARD_RESTORED_MS = 200;
const KEYBOARD_SHRINK_PX = 80;
const ECHO_MS = 300;
const ECHO_PX = 2;
const TOUCH_STALE_MS = 5000;
const REVEAL_GAP = 16;
const ZOOM_TOLERANCE = 0.01;

export interface Box {
  top: number;
  bottom: number;
}

export interface ViewportReading {
  innerHeight: number;
  rootClientHeight: number;
  scrollY?: number;
  visual: {
    height: number;
    offsetTop: number;
    scale: number;
    pageTop?: number;
  } | null;
}

export interface VisibleArea extends Box {
  height: number;
  scale: number;
}

export interface LayoutReading {
  viewport: ViewportReading;
  scroller: Box | null;
  navigation: (Box & { height: number }) | null;
  header?: Box | null;
  composer: Box | null;
  end: Box;
}

const finite = (value: number | undefined, fallback: number) =>
  typeof value === 'number' && Number.isFinite(value) ? value : fallback;

const scrollYIsVisualTop = ({ scrollY, visual }: ViewportReading) => {
  if (!visual || typeof scrollY !== 'number') return false;
  const { pageTop } = visual;
  return (
    typeof pageTop === 'number' &&
    finite(visual.offsetTop, 0) > 2 &&
    Math.abs(pageTop - scrollY) <= 2
  );
};

export const rectsInLayoutViewport = (viewport: ViewportReading) => {
  const { innerHeight, rootClientHeight, visual } = viewport;
  return (
    visual !== null &&
    rootClientHeight > 0 &&
    innerHeight >= rootClientHeight - 2 &&
    innerHeight > finite(visual.height, innerHeight) + 2 &&
    !scrollYIsVisualTop(viewport)
  );
};

const pageScale = (scale: number) =>
  Math.abs(scale - 1) < ZOOM_TOLERANCE ? 1 : scale;

export const visibleArea = (viewport: ViewportReading): VisibleArea => {
  const { innerHeight, visual } = viewport;
  if (!visual)
    return { top: 0, bottom: innerHeight, height: innerHeight, scale: 1 };
  const height = finite(visual.height, innerHeight);
  const top = rectsInLayoutViewport(viewport) ? finite(visual.offsetTop, 0) : 0;
  return {
    top,
    bottom: top + height,
    height,
    scale: pageScale(finite(visual.scale, 1)),
  };
};

export const contentBounds = (layout: LayoutReading): Box => {
  const area = visibleArea(layout.viewport);
  let { top, bottom } = area;
  if (layout.scroller) {
    top = Math.max(top, layout.scroller.top);
    bottom = Math.min(bottom, layout.scroller.bottom);
  }
  const header = layout.header;
  if (header && header.top <= top + 2 && header.bottom > top)
    top = Math.max(top, header.bottom);
  const navigation = layout.navigation;
  if (navigation && navigation.height > 0) {
    const { innerHeight } = layout.viewport;
    if (
      area.bottom > innerHeight + 2 &&
      Math.abs(navigation.bottom - innerHeight) <= 2
    )
      bottom = Math.min(bottom, area.bottom - navigation.height);
    else if (
      navigation.top <= area.bottom &&
      navigation.bottom >= area.bottom - 2
    )
      bottom = Math.min(bottom, navigation.top);
  }
  return { top, bottom };
};

export const distanceFromNewest = (layout: LayoutReading) =>
  layout.end.bottom - contentBounds(layout).bottom;

export const isAtNewest = (layout: LayoutReading) =>
  distanceFromNewest(layout) <= AT_NEWEST_TOLERANCE;

export const rectVisible = (layout: LayoutReading, rect: Box) => {
  if (visibleArea(layout.viewport).scale !== 1 || !layout.composer)
    return false;
  const bounds = contentBounds(layout);
  return (
    rect.bottom > bounds.top &&
    rect.top < Math.min(bounds.bottom, layout.composer.top)
  );
};

export const rectShown = (layout: LayoutReading, rect: Box) => {
  if (visibleArea(layout.viewport).scale !== 1 || !layout.composer)
    return false;
  const bounds = contentBounds(layout);
  return (
    rect.top >= bounds.top &&
    rect.bottom <= Math.min(bounds.bottom, layout.composer.top)
  );
};

export const viewportRestsOnKeyboard = (viewport: ViewportReading) => {
  const area = visibleArea(viewport);
  return (
    rectsInLayoutViewport(viewport) &&
    area.height < viewport.innerHeight - KEYBOARD_SHRINK_PX &&
    area.top >= viewport.innerHeight - area.height - 2
  );
};

const keyboardShown = (viewport: ViewportReading) =>
  rectsInLayoutViewport(viewport)
    ? viewportRestsOnKeyboard(viewport)
    : viewport.rootClientHeight > 0 &&
      visibleArea(viewport).height <
        viewport.rootClientHeight - KEYBOARD_SHRINK_PX;

export const keyboardLift = (viewport: ViewportReading, rested: boolean) => {
  const area = visibleArea(viewport);
  if (rectsInLayoutViewport(viewport))
    return rested ? Math.max(0, viewport.innerHeight - area.bottom) : 0;
  const fixedBottom =
    viewport.visual && viewport.rootClientHeight > 0
      ? Math.min(
          viewport.innerHeight,
          viewport.rootClientHeight - finite(viewport.visual.offsetTop, 0),
        )
      : viewport.innerHeight;
  return Math.max(0, fixedBottom - area.bottom);
};

export const keyboardRoom = (viewport: ViewportReading) => {
  const { visual, innerHeight, rootClientHeight } = viewport;
  if (!visual || rootClientHeight <= 0 || rectsInLayoutViewport(viewport))
    return 0;
  if (visibleArea(viewport).scale !== 1 || !keyboardShown(viewport)) return 0;
  const room = innerHeight + finite(visual.offsetTop, 0) - rootClientHeight;
  return room >= 1 ? room : 0;
};

export const revealAmount = ({
  last,
  composer,
  remaining,
}: {
  last: Box | null;
  composer: Box | null;
  remaining: number;
}) => {
  if (!last || !composer) return 0;
  const amount = Math.min(
    last.bottom - composer.top + REVEAL_GAP,
    Math.max(0, remaining),
  );
  return amount >= 1 ? amount : 0;
};

export interface Snapshot {
  scale: number;
  height: number;
  composerFocused: boolean;
  scrollTop: number;
  distance: number;
  reveal: number;
  viewport: ViewportReading;
  ownScroller: boolean;
  firstMessage: { id: string; top: number } | null;
  messageTop: (id: string) => number | null;
  messageShown: (id: string) => boolean;
  remaining: number;
}

export interface Target {
  id: string;
  fromSearch: boolean;
  phase: 'seeking' | 'landed';
}

export interface KeyboardSession {
  restoreTop: number | null;
  following: boolean;
  baseHeight: number;
  shrunk: boolean;
  closing: boolean;
  rested: boolean;
  room: number;
}

export interface ScrollState {
  following: boolean;
  target: Target | null;
  searchEntry: boolean;
  screen: string | null;
  ownJump: boolean;
  stillJump: boolean;
  zoomedAway: boolean;
  userScrolling: boolean;
  touching: boolean;
  pendingFollow: boolean;
  anchor: { id: string; top: number; scrollTop: number } | null;
  keyboard: KeyboardSession | null;
  echo: { height: number } | null;
  scale: number;
  height: number;
}

export type TimerName =
  | 'ownJumpEnd'
  | 'highlightEnd'
  | 'userScrollEnd'
  | 'keyboardClose'
  | 'echoEnd'
  | 'touchStale';

export type Command =
  | { type: 'alignEnd' }
  | { type: 'reveal'; by: number }
  | { type: 'scrollBy'; by: number }
  | { type: 'scrollToMessage'; id: string }
  | { type: 'restoreScroll'; top: number }
  | { type: 'away'; value: boolean }
  | { type: 'read'; kind: 'check' | 'return' | 'newest' }
  | { type: 'forgetSearch' }
  | { type: 'lift'; by: number | null }
  | { type: 'room'; by: number | null }
  | { type: 'timer'; name: TimerName; delay: number }
  | { type: 'clearTimer'; name: TimerName };

export type ScrollEvent =
  | { type: 'attached' }
  | { type: 'detached' }
  | { type: 'newestShown'; screen: string; mine: boolean }
  | { type: 'targetLoaded'; id: string }
  | { type: 'targetScrolled'; id: string; movedUp: boolean; moved: boolean }
  | { type: 'targetMissing' }
  | { type: 'quoteClicked'; id: string }
  | { type: 'jumpToNewest' }
  | { type: 'userIntent'; touch: boolean }
  | { type: 'touch'; down: boolean }
  | { type: 'pageAction'; quote?: string }
  | { type: 'scrolled' }
  | { type: 'viewportScrolled' }
  | { type: 'scrollEnded' }
  | { type: 'composerFocused' }
  | { type: 'composerBlurred' }
  | { type: 'viewportResized' }
  | { type: 'contentResized' }
  | { type: 'olderArriving' }
  | { type: 'olderLoaded' }
  | { type: 'roomMade' }
  | { type: 'timer'; name: TimerName };

export const initialScrollState = (targetId: string | null): ScrollState => ({
  following: !targetId,
  target: targetId
    ? { id: targetId, fromSearch: true, phase: 'seeking' }
    : null,
  searchEntry: Boolean(targetId),
  screen: null,
  ownJump: false,
  stillJump: false,
  zoomedAway: false,
  userScrolling: false,
  touching: false,
  pendingFollow: false,
  anchor: null,
  keyboard: null,
  echo: null,
  scale: 1,
  height: 0,
});

const seeking = (state: ScrollState) => state.target?.phase === 'seeking';

const toNewest = (
  state: ScrollState,
  s: Snapshot,
  commands: Command[],
  automatic: boolean,
) => {
  if (automatic) {
    if (s.scale !== 1) return;
    if (state.userScrolling || state.touching) {
      state.pendingFollow = true;
      return;
    }
  }
  state.pendingFollow = false;
  if (!s.composerFocused) {
    commands.push({ type: 'alignEnd' });
    return;
  }
  const by = s.reveal;
  if (by < 1) return;
  commands.push({ type: 'reveal', by });
  state.echo = { height: s.height };
  commands.push({ type: 'timer', name: 'echoEnd', delay: ECHO_MS });
};

const isEcho = (state: ScrollState, s: Snapshot) =>
  state.echo !== null &&
  s.height < state.echo.height &&
  state.echo.height - s.height <= ECHO_PX;

const forgetSearch = (state: ScrollState, commands: Command[]) => {
  if (!state.searchEntry) return;
  state.searchEntry = false;
  commands.push({ type: 'forgetSearch' });
};

const setFollowing = (
  state: ScrollState,
  following: boolean,
  commands: Command[],
) => {
  state.following = following;
  if (!following) state.pendingFollow = false;
  else forgetSearch(state, commands);
  commands.push({ type: 'away', value: !following });
};

const raise = (state: ScrollState, s: Snapshot, commands: Command[]) => {
  const keyboard = state.keyboard;
  if (!keyboard) return;
  if (
    s.ownScroller ||
    !s.viewport.visual ||
    visibleArea(s.viewport).scale !== 1
  ) {
    commands.push({ type: 'lift', by: null });
    return;
  }
  if (keyboardShown(s.viewport)) keyboard.rested = true;
  commands.push({
    type: 'lift',
    by: keyboardLift(s.viewport, keyboard.rested),
  });
  if (
    keyboard.room ||
    !state.following ||
    seeking(state) ||
    !s.composerFocused ||
    s.remaining > 1
  )
    return;
  const room = keyboardRoom(s.viewport);
  if (!room) return;
  keyboard.room = room;
  commands.push({ type: 'room', by: room });
};

const measureJump = (state: ScrollState, s: Snapshot, commands: Command[]) => {
  if (s.scale !== 1) return;
  const following = s.distance <= AT_NEWEST_TOLERANCE;
  const was = state.following;
  if (state.keyboard) state.keyboard.following = following;
  setFollowing(state, following, commands);
  if (following && !was) commands.push({ type: 'read', kind: 'return' });
};

const trackPosition = (
  state: ScrollState,
  s: Snapshot,
  commands: Command[],
) => {
  if (s.scale !== 1) {
    state.zoomedAway = true;
    if (state.keyboard) {
      state.keyboard.following = false;
      state.keyboard.restoreTop = null;
    }
    setFollowing(state, false, commands);
    return;
  }
  if (state.ownJump) {
    const following = s.distance <= AT_NEWEST_TOLERANCE;
    if (state.keyboard && !following) state.keyboard.following = false;
    setFollowing(state, following, commands);
    return;
  }
  if (seeking(state)) return;
  if (state.keyboard && !state.userScrolling) return;
  const following = s.distance < FOLLOW_NEWEST_DISTANCE;
  if (state.userScrolling)
    commands.push({
      type: 'timer',
      name: 'userScrollEnd',
      delay: USER_SCROLL_SETTLE_MS,
    });
  if (state.keyboard) {
    if (state.keyboard.restoreTop !== null)
      state.keyboard.restoreTop = s.scrollTop;
    state.keyboard.following = following;
  }
  setFollowing(state, following, commands);
  if (following) commands.push({ type: 'read', kind: 'return' });
};

const endUserScroll = (
  state: ScrollState,
  s: Snapshot,
  commands: Command[],
) => {
  if (state.touching) return;
  state.userScrolling = false;
  commands.push({ type: 'clearTimer', name: 'userScrollEnd' });
  if (!state.pendingFollow) return;
  state.pendingFollow = false;
  if (state.following && !seeking(state)) toNewest(state, s, commands, true);
};

const liftFinger = (state: ScrollState, s: Snapshot, commands: Command[]) => {
  state.touching = false;
  commands.push({ type: 'clearTimer', name: 'touchStale' });
  if (state.userScrolling)
    commands.push({
      type: 'timer',
      name: 'userScrollEnd',
      delay: USER_SCROLL_SETTLE_MS,
    });
  else endUserScroll(state, s, commands);
};

const closeKeyboard = (
  state: ScrollState,
  s: Snapshot,
  commands: Command[],
) => {
  const keyboard = state.keyboard;
  if (!keyboard) return;
  if (keyboard.room) commands.push({ type: 'room', by: null });
  if (s.scale === 1) {
    if (!keyboard.following && keyboard.restoreTop !== null) {
      commands.push({ type: 'restoreScroll', top: keyboard.restoreTop });
      setFollowing(state, false, commands);
    } else if (keyboard.following && state.following) {
      toNewest(state, s, commands, false);
    } else if (
      !state.following &&
      state.stillJump &&
      keyboard.restoreTop === null &&
      !seeking(state) &&
      s.distance <= AT_NEWEST_TOLERANCE
    ) {
      setFollowing(state, true, commands);
      commands.push({ type: 'read', kind: 'return' });
    }
  }
  state.keyboard = null;
  commands.push({ type: 'clearTimer', name: 'keyboardClose' });
  commands.push({ type: 'lift', by: null });
};

export const step = (
  previous: ScrollState,
  event: ScrollEvent,
  s: Snapshot,
): { state: ScrollState; commands: Command[] } => {
  const state: ScrollState = {
    ...previous,
    keyboard: previous.keyboard && { ...previous.keyboard },
  };
  const commands: Command[] = [];

  switch (event.type) {
    case 'attached':
      state.scale = s.scale;
      state.height = s.height;
      break;

    case 'detached':
      if (state.keyboard) commands.push({ type: 'lift', by: null });
      if (state.keyboard?.room) commands.push({ type: 'room', by: null });
      state.keyboard = null;
      state.userScrolling = false;
      state.touching = false;
      state.pendingFollow = false;
      state.anchor = null;
      state.ownJump = false;
      state.stillJump = false;
      state.zoomedAway = false;
      state.echo = null;
      for (const name of [
        'keyboardClose',
        'userScrollEnd',
        'echoEnd',
        'ownJumpEnd',
        'touchStale',
      ] as const)
        commands.push({ type: 'clearTimer', name });
      break;

    case 'newestShown': {
      const opening = state.screen !== event.screen;
      if (opening) {
        state.screen = event.screen;
        state.following = !seeking(state);
        if (state.following) commands.push({ type: 'away', value: false });
      }
      if (seeking(state) || !state.following) break;
      if (opening) {
        if (s.scale === 1) toNewest(state, s, commands, false);
      } else {
        toNewest(state, s, commands, true);
      }
      break;
    }

    case 'targetLoaded':
      if (state.target?.id !== event.id || !seeking(state)) break;
      if (state.keyboard) state.keyboard.restoreTop = null;
      commands.push({ type: 'scrollToMessage', id: event.id });
      break;

    case 'targetScrolled': {
      if (state.target?.id !== event.id || !seeking(state)) break;
      if (state.target.fromSearch) forgetSearch(state, commands);
      state.target = { ...state.target, phase: 'landed' };
      state.ownJump = true;
      state.stillJump = !event.moved;
      const following =
        !event.movedUp && s.scale === 1 && s.distance <= AT_NEWEST_TOLERANCE;
      if (state.keyboard) state.keyboard.following = following;
      setFollowing(state, following, commands);
      commands.push({ type: 'timer', name: 'ownJumpEnd', delay: OWN_JUMP_MS });
      commands.push({
        type: 'timer',
        name: 'highlightEnd',
        delay: HIGHLIGHT_DURATION_MS,
      });
      if (following) commands.push({ type: 'read', kind: 'return' });
      break;
    }

    case 'targetMissing': {
      if (!state.target || !seeking(state)) break;
      const fromSearch = state.target.fromSearch;
      state.target = null;
      if (!fromSearch) break;
      setFollowing(state, true, commands);
      toNewest(state, s, commands, false);
      commands.push({ type: 'read', kind: 'newest' });
      break;
    }

    case 'quoteClicked':
      if (!event.id || state.target?.id === event.id) break;
      state.ownJump = false;
      state.stillJump = false;
      commands.push({ type: 'clearTimer', name: 'ownJumpEnd' });
      commands.push({ type: 'clearTimer', name: 'highlightEnd' });
      if (s.messageShown(event.id)) {
        state.target = { id: event.id, fromSearch: false, phase: 'landed' };
        commands.push({
          type: 'timer',
          name: 'highlightEnd',
          delay: HIGHLIGHT_DURATION_MS,
        });
        break;
      }
      state.target = { id: event.id, fromSearch: false, phase: 'seeking' };
      setFollowing(state, false, commands);
      break;

    case 'jumpToNewest':
      if (seeking(state)) state.target = null;
      state.ownJump = false;
      state.stillJump = false;
      commands.push({ type: 'clearTimer', name: 'ownJumpEnd' });
      if (state.keyboard) {
        state.keyboard.restoreTop = null;
        state.keyboard.following = true;
      }
      setFollowing(state, true, commands);
      toNewest(state, s, commands, false);
      commands.push({ type: 'read', kind: 'return' });
      break;

    case 'userIntent':
      state.ownJump = false;
      state.stillJump = false;
      commands.push({ type: 'clearTimer', name: 'ownJumpEnd' });
      if (seeking(state)) state.target = null;
      state.userScrolling = true;
      commands.push({
        type: 'timer',
        name: 'userScrollEnd',
        delay: USER_SCROLL_SETTLE_MS,
      });
      if (event.touch) {
        state.touching = true;
        commands.push({
          type: 'timer',
          name: 'touchStale',
          delay: TOUCH_STALE_MS,
        });
      }
      break;

    case 'touch':
      if (event.down) {
        state.touching = true;
        commands.push({
          type: 'timer',
          name: 'touchStale',
          delay: TOUCH_STALE_MS,
        });
      } else if (state.touching) {
        liftFinger(state, s, commands);
      }
      break;

    case 'pageAction':
      if (state.keyboard && !event.quote) state.keyboard.restoreTop = null;
      break;

    case 'scrolled':
      trackPosition(state, s, commands);
      break;

    case 'viewportScrolled':
      if (state.keyboard) {
        raise(state, s, commands);
        if (state.userScrolling) trackPosition(state, s, commands);
      }
      if (state.ownJump && state.stillJump) measureJump(state, s, commands);
      commands.push({ type: 'read', kind: 'check' });
      break;

    case 'scrollEnded':
      if (!state.userScrolling) break;
      trackPosition(state, s, commands);
      endUserScroll(state, s, commands);
      break;

    case 'composerFocused':
      if (state.keyboard) {
        state.keyboard.closing = false;
        commands.push({ type: 'clearTimer', name: 'keyboardClose' });
        break;
      }
      if (
        state.following &&
        !seeking(state) &&
        s.scale === 1 &&
        s.distance > AT_NEWEST_TOLERANCE
      )
        toNewest(state, s, commands, false);
      state.keyboard = {
        restoreTop: s.scrollTop,
        following: state.following,
        baseHeight: s.height,
        shrunk: false,
        closing: false,
        rested: false,
        room: 0,
      };
      raise(state, s, commands);
      break;

    case 'composerBlurred':
      if (!state.keyboard) break;
      state.keyboard.closing = true;
      commands.push({
        type: 'timer',
        name: 'keyboardClose',
        delay: KEYBOARD_BLUR_MS,
      });
      break;

    case 'viewportResized': {
      const scaleChanged = s.scale !== state.scale;
      const heightChanged = s.height !== state.height;
      state.scale = s.scale;
      state.height = s.height;
      if (state.keyboard) raise(state, s, commands);
      if (state.ownJump && state.stillJump && !scaleChanged)
        measureJump(state, s, commands);
      if (scaleChanged && s.scale === 1 && state.zoomedAway) {
        state.zoomedAway = false;
        if (s.distance < FOLLOW_NEWEST_DISTANCE && !state.target) {
          if (state.keyboard) state.keyboard.following = true;
          setFollowing(state, true, commands);
          commands.push({ type: 'read', kind: 'return' });
        }
      }
      const keyboard = state.keyboard;
      if (keyboard) {
        if (s.scale === 1 && !scaleChanged) {
          if (
            heightChanged &&
            state.following &&
            s.composerFocused &&
            !state.userScrolling
          ) {
            if (isEcho(state, s)) state.echo = { height: s.height };
            else toNewest(state, s, commands, true);
          }
          if (s.height < keyboard.baseHeight - KEYBOARD_SHRINK_PX)
            keyboard.shrunk = true;
          const { rootClientHeight } = s.viewport;
          const closed =
            s.height >= keyboard.baseHeight - 2 ||
            (rootClientHeight > 0 &&
              s.height >= rootClientHeight - 2 &&
              s.height >= keyboard.baseHeight - KEYBOARD_SHRINK_PX);
          if (keyboard.shrunk && closed) {
            keyboard.closing = true;
            commands.push({
              type: 'timer',
              name: 'keyboardClose',
              delay: KEYBOARD_RESTORED_MS,
            });
          } else if (keyboard.closing) {
            commands.push({
              type: 'timer',
              name: 'keyboardClose',
              delay: KEYBOARD_BLUR_MS,
            });
          }
        }
        commands.push({ type: 'read', kind: 'check' });
        break;
      }
      if (
        s.scale === 1 &&
        !scaleChanged &&
        heightChanged &&
        state.following &&
        !state.userScrolling
      )
        toNewest(state, s, commands, true);
      break;
    }

    case 'contentResized':
      if (
        state.following &&
        !seeking(state) &&
        s.scale === 1 &&
        (!state.keyboard || s.composerFocused)
      ) {
        toNewest(state, s, commands, true);
        commands.push({ type: 'read', kind: 'check' });
      }
      break;

    case 'olderArriving': {
      const first = state.following ? null : s.firstMessage;
      state.anchor = first && { ...first, scrollTop: s.scrollTop };
      break;
    }

    case 'olderLoaded': {
      const anchor = state.anchor;
      if (!anchor) break;
      state.anchor = null;
      const top = s.messageTop(anchor.id);
      if (top === null) break;
      const by = top - anchor.top;
      if (Math.abs(by) >= 1) commands.push({ type: 'scrollBy', by });
      const grown = top + s.scrollTop - (anchor.top + anchor.scrollTop);
      const keyboard = state.keyboard;
      if (keyboard && keyboard.restoreTop !== null && Math.abs(grown) >= 1)
        keyboard.restoreTop += grown;
      break;
    }

    case 'roomMade':
      if (
        state.keyboard &&
        state.following &&
        !seeking(state) &&
        s.composerFocused
      )
        toNewest(state, s, commands, true);
      break;

    case 'timer':
      switch (event.name) {
        case 'ownJumpEnd':
          state.ownJump = false;
          break;
        case 'highlightEnd':
          if (state.target?.phase === 'landed') state.target = null;
          state.stillJump = false;
          break;
        case 'userScrollEnd':
          endUserScroll(state, s, commands);
          break;
        case 'keyboardClose':
          closeKeyboard(state, s, commands);
          break;
        case 'echoEnd':
          state.echo = null;
          break;
        case 'touchStale':
          if (state.touching) liftFinger(state, s, commands);
          break;
      }
      break;
  }

  return { state, commands };
};
