// Where a room is scrolled to, and whether it keeps up with the newest message, is decided here and nowhere else.
// Nothing in this file touches the page: it reads what was measured and says what to do. The hook in
// use_chat_scroll.ts measures, passes each happening on to `step`, and carries out what comes back.

export const FOLLOW_NEWEST_DISTANCE = 240;
// How far below the visible bottom the end may be and still count as the newest being in view.
export const AT_NEWEST_TOLERANCE = 2;
export const HIGHLIGHT_DURATION_MS = 3000;
// A jump's own scroll events arrive after it; until then they are not the reader's.
const OWN_JUMP_MS = 200;
// A scroll event within this time of the last one belongs to the same scroll, inertia included.
const USER_SCROLL_SETTLE_MS = 200;
const KEYBOARD_BLUR_MS = 700;
const KEYBOARD_RESTORED_MS = 200;
const KEYBOARD_SHRINK_PX = 80;
// Safari answers a scroll at the end of the page by shrinking its visual viewport, soon after it.
const ECHO_MS = 300;
// Room left between the last message and the composer when revealing it over the keyboard.
const REVEAL_GAP = 16;

export interface Box {
  top: number;
  bottom: number;
}

export interface ViewportReading {
  innerHeight: number;
  // The root element's clientHeight, or 0 where it is not known.
  rootClientHeight: number;
  visual: { height: number; offsetTop: number; scale: number } | null;
}

export interface VisibleArea extends Box {
  height: number;
  scale: number;
}

export interface LayoutReading {
  viewport: ViewportReading;
  // The room's own scrolling box, when it does not scroll with the page.
  scroller: Box | null;
  navigation: (Box & { height: number }) | null;
  composer: Box | null;
  end: Box;
}

const finite = (value: number | undefined, fallback: number) =>
  typeof value === 'number' && Number.isFinite(value) ? value : fallback;

// What of the page is on the screen, in the coordinates element rectangles use.
// Chrome keeps the layout viewport (and innerHeight) at the page's height and gives rectangles relative to it, so the
// visual viewport starts offsetTop below their origin. Safari shrinks innerHeight with the keyboard (or grows it with
// a collapsed toolbar) and gives rectangles relative to what is on the screen, whatever offsetTop it reports.
export const visibleArea = ({
  innerHeight,
  rootClientHeight,
  visual,
}: ViewportReading): VisibleArea => {
  if (!visual)
    return { top: 0, bottom: innerHeight, height: innerHeight, scale: 1 };
  const height = finite(visual.height, innerHeight);
  const layoutCoordinates =
    rootClientHeight > 0 &&
    innerHeight >= rootClientHeight - 2 &&
    innerHeight > height + 2;
  const top = layoutCoordinates ? finite(visual.offsetTop, 0) : 0;
  return { top, bottom: top + height, height, scale: finite(visual.scale, 1) };
};

// What of the room can be seen: within the visible area and the room's own scrolling box, above a navigation bar
// resting on the bottom of the screen.
export const contentBounds = (layout: LayoutReading): Box => {
  const area = visibleArea(layout.viewport);
  let { top, bottom } = area;
  if (layout.scroller) {
    top = Math.max(top, layout.scroller.top);
    bottom = Math.min(bottom, layout.scroller.bottom);
  }
  const navigation = layout.navigation;
  if (
    navigation &&
    navigation.height > 0 &&
    navigation.top <= area.bottom &&
    navigation.bottom >= area.bottom - 2
  )
    bottom = Math.min(bottom, navigation.top);
  return { top, bottom };
};

// How far the end of the room is below what can be seen. The end comes right after the composer: in view, it means
// the composer rests in its place with the newest message just above it, however much the page has below it.
export const distanceFromNewest = (layout: LayoutReading) =>
  layout.end.bottom - contentBounds(layout).bottom;

export const isAtNewest = (layout: LayoutReading) =>
  distanceFromNewest(layout) <= AT_NEWEST_TOLERANCE;

// Whether a message can actually be seen: not zoomed, and not under the composer.
export const rectVisible = (layout: LayoutReading, rect: Box) => {
  if (visibleArea(layout.viewport).scale !== 1 || !layout.composer)
    return false;
  const bounds = contentBounds(layout);
  return (
    rect.bottom > bounds.top &&
    rect.top < Math.min(bounds.bottom, layout.composer.top)
  );
};

// How far the composer and the navigation bar are to be raised to sit on the bottom of the visible area: iOS grows
// innerHeight below it while the keyboard is open, and Android moves the visual viewport up within the page.
export const keyboardLift = (viewport: ViewportReading) =>
  Math.max(0, viewport.innerHeight - visibleArea(viewport).bottom);

// How far to scroll to bring the last message out from under the composer while the keyboard is open. Never past the
// end of the page, which Safari answers by shrinking its viewport, and never less than a pixel, which moves nothing.
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

// What the hook measured when something happened. Read lazily there, so only what a decision needs is measured.
export interface Snapshot {
  scale: number;
  // The visual viewport's height, or innerHeight.
  height: number;
  // The touch keyboard is up for the composer's text box.
  composerFocused: boolean;
  scrollTop: number;
  distance: number;
  // What revealing the last message over the keyboard would scroll by, 0 when nothing.
  reveal: number;
}

export interface Target {
  id: string;
  fromSearch: boolean;
  // Seeking until it is scrolled to, then highlighted for a while.
  phase: 'seeking' | 'landed';
}

export interface KeyboardSession {
  // Where to go back to when it closes, or null when an explicit move took over.
  restoreTop: number | null;
  following: boolean;
  baseHeight: number;
  shrunk: boolean;
  closing: boolean;
}

export interface ScrollState {
  following: boolean;
  target: Target | null;
  screen: string | null;
  ownJump: boolean;
  zoomedAway: boolean;
  userScrolling: boolean;
  pendingFollow: boolean;
  keyboard: KeyboardSession | null;
  echo: { height: number; amount: number } | null;
  scale: number;
  height: number;
}

export type TimerName =
  | 'ownJumpEnd'
  | 'highlightEnd'
  | 'userScrollEnd'
  | 'keyboardClose'
  | 'echoEnd';

export type Command =
  | { type: 'alignEnd' }
  | { type: 'reveal'; by: number }
  | { type: 'scrollToMessage'; id: string }
  | { type: 'restoreScroll'; top: number }
  | { type: 'away'; value: boolean }
  | { type: 'read'; kind: 'check' | 'return' | 'newest' }
  | { type: 'lift'; on: boolean }
  | { type: 'timer'; name: TimerName; delay: number }
  | { type: 'clearTimer'; name: TimerName };

export type ScrollEvent =
  | { type: 'attached' }
  | { type: 'detached' }
  | { type: 'newestShown'; screen: string; mine: boolean }
  | { type: 'targetLoaded'; id: string }
  | { type: 'targetScrolled'; id: string; movedUp: boolean }
  | { type: 'targetMissing' }
  | { type: 'quoteClicked'; id: string }
  | { type: 'jumpToNewest' }
  | { type: 'userIntent' }
  | { type: 'pageAction' }
  | { type: 'scrolled' }
  | { type: 'viewportScrolled' }
  | { type: 'scrollEnded' }
  | { type: 'composerFocused' }
  | { type: 'composerBlurred' }
  | { type: 'viewportResized' }
  | { type: 'contentResized' }
  | { type: 'olderLoaded' }
  | { type: 'timer'; name: TimerName };

export const initialScrollState = (targetId: string | null): ScrollState => ({
  following: !targetId,
  target: targetId
    ? { id: targetId, fromSearch: true, phase: 'seeking' }
    : null,
  screen: null,
  ownJump: false,
  zoomedAway: false,
  userScrolling: false,
  pendingFollow: false,
  keyboard: null,
  echo: null,
  scale: 1,
  height: 0,
});

const seeking = (state: ScrollState) => state.target?.phase === 'seeking';

// Brings the newest message into view. What follows by itself waits while the reader is scrolling, and is never
// done zoomed in; what the reader asked for is done at once.
const toNewest = (
  state: ScrollState,
  s: Snapshot,
  commands: Command[],
  automatic: boolean,
) => {
  if (automatic) {
    if (s.scale !== 1) return;
    if (state.userScrolling) {
      state.pendingFollow = true;
      return;
    }
  }
  state.pendingFollow = false;
  if (!s.composerFocused) {
    commands.push({ type: 'alignEnd' });
    return;
  }
  // Scrolling to the end of the page with the keyboard open pulls what is under Safari's toolbar above it.
  const by = s.reveal;
  if (by < 1) return;
  commands.push({ type: 'reveal', by });
  state.echo = { height: s.height, amount: by };
  commands.push({ type: 'timer', name: 'echoEnd', delay: ECHO_MS });
};

// A visual viewport that shrank, soon after a reveal, by no more than it scrolled: Safari answering it.
const isEcho = (state: ScrollState, s: Snapshot) =>
  state.echo !== null &&
  s.height < state.echo.height &&
  state.echo.height - s.height <= state.echo.amount + 1;

const setFollowing = (
  state: ScrollState,
  following: boolean,
  commands: Command[],
) => {
  state.following = following;
  if (!following) state.pendingFollow = false;
  commands.push({ type: 'away', value: !following });
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
  // With the keyboard open Safari scrolls by itself to show the box; only the reader's own scrolling counts.
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
  state.userScrolling = false;
  commands.push({ type: 'clearTimer', name: 'userScrollEnd' });
  if (!state.pendingFollow) return;
  state.pendingFollow = false;
  if (state.following && !seeking(state)) toNewest(state, s, commands, true);
};

const closeKeyboard = (
  state: ScrollState,
  s: Snapshot,
  commands: Command[],
) => {
  const keyboard = state.keyboard;
  if (!keyboard) return;
  if (s.scale === 1) {
    if (!keyboard.following && keyboard.restoreTop !== null) {
      commands.push({ type: 'restoreScroll', top: keyboard.restoreTop });
      setFollowing(state, false, commands);
    } else if (keyboard.following && state.following) {
      toNewest(state, s, commands, false);
    }
  }
  state.keyboard = null;
  commands.push({ type: 'clearTimer', name: 'keyboardClose' });
  commands.push({ type: 'lift', on: false });
};

// The next state, and what to do, for something that happened in the room.
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
      if (state.keyboard) commands.push({ type: 'lift', on: false });
      state.keyboard = null;
      state.userScrolling = false;
      state.pendingFollow = false;
      state.ownJump = false;
      state.zoomedAway = false;
      state.echo = null;
      for (const name of [
        'keyboardClose',
        'userScrollEnd',
        'echoEnd',
        'ownJumpEnd',
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
      // Opening is aligned to the newest even while zoomed out of it, as it always was; arrivals wait.
      if (opening) {
        if (s.scale === 1) toNewest(state, s, commands, false);
      } else {
        toNewest(state, s, commands, true);
      }
      break;
    }

    case 'targetLoaded':
      if (state.target?.id !== event.id || !seeking(state)) break;
      // Going to the original is an explicit move: closing the keyboard must not undo it.
      if (state.keyboard) state.keyboard.restoreTop = null;
      commands.push({ type: 'scrollToMessage', id: event.id });
      break;

    case 'targetScrolled': {
      if (state.target?.id !== event.id || !seeking(state)) break;
      state.target = { ...state.target, phase: 'landed' };
      state.ownJump = true;
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
      state.target = { id: event.id, fromSearch: false, phase: 'seeking' };
      state.ownJump = false;
      commands.push({ type: 'clearTimer', name: 'ownJumpEnd' });
      commands.push({ type: 'clearTimer', name: 'highlightEnd' });
      setFollowing(state, false, commands);
      break;

    case 'jumpToNewest':
      if (seeking(state)) state.target = null;
      state.ownJump = false;
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
      commands.push({ type: 'clearTimer', name: 'ownJumpEnd' });
      // A target still on its way no longer takes the reader anywhere.
      if (seeking(state)) state.target = null;
      state.userScrolling = true;
      commands.push({
        type: 'timer',
        name: 'userScrollEnd',
        delay: USER_SCROLL_SETTLE_MS,
      });
      break;

    case 'pageAction':
      if (state.keyboard) state.keyboard.restoreTop = null;
      break;

    case 'scrolled':
      trackPosition(state, s, commands);
      break;

    case 'viewportScrolled':
      if (state.keyboard) {
        commands.push({ type: 'lift', on: true });
        if (state.userScrolling) trackPosition(state, s, commands);
      }
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
      state.keyboard = {
        restoreTop: s.scrollTop,
        following: state.following,
        baseHeight: s.height,
        shrunk: false,
        closing: false,
      };
      commands.push({ type: 'lift', on: true });
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
      if (state.keyboard) commands.push({ type: 'lift', on: true });
      if (scaleChanged && s.scale === 1 && state.zoomedAway) {
        state.zoomedAway = false;
        if (s.distance <= AT_NEWEST_TOLERANCE && !state.target) {
          if (state.keyboard) state.keyboard.following = true;
          setFollowing(state, true, commands);
          commands.push({ type: 'read', kind: 'return' });
        }
      }
      const keyboard = state.keyboard;
      if (keyboard) {
        if (s.scale === 1 && !scaleChanged) {
          if (heightChanged && state.following && s.composerFocused) {
            if (isEcho(state, s)) state.echo = null;
            else toNewest(state, s, commands, true);
          }
          if (s.height < keyboard.baseHeight - KEYBOARD_SHRINK_PX)
            keyboard.shrunk = true;
          if (keyboard.shrunk && s.height >= keyboard.baseHeight - 2) {
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
      if (s.scale === 1 && !scaleChanged && heightChanged && state.following)
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

    // The browser keeps the reader's place as older messages come in above (rule 5). Following, the content
    // growing keeps the newest in view.
    case 'olderLoaded':
      break;

    case 'timer':
      switch (event.name) {
        case 'ownJumpEnd':
          state.ownJump = false;
          break;
        case 'highlightEnd':
          if (state.target?.phase === 'landed') state.target = null;
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
      }
      break;
  }

  return { state, commands };
};
