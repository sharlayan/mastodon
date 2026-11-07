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
// What Safari's answer to a scroll at the end of the page shrinks its viewport by, each time (iOS diagnostics: 1px).
const ECHO_PX = 2;
// A finger is taken to have left the screen when nothing is heard of it for this long (a touchend can be lost when
// what it was on goes away).
const TOUCH_STALE_MS = 5000;
// Room left between the last message and the composer when revealing it over the keyboard.
const REVEAL_GAP = 16;
// A pinch let go just short of 1 is not zoomed in: the page looks the same (SE 3 stayed at 1.0033 for 20s).
const ZOOM_TOLERANCE = 0.01;

export interface Box {
  top: number;
  bottom: number;
}

export interface ViewportReading {
  innerHeight: number;
  // The root element's clientHeight, or 0 where it is not known.
  rootClientHeight: number;
  // window.scrollY, where it is known.
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
// Safari can also keep innerHeight and report an offsetTop while its scrollY is already the top of what is shown
// (pageTop) and rectangles are relative to that: focused far up, or reading on with the keyboard open (iPhone on
// ddbad17ba3: offsetTop 262 with pageTop 1937.5 at scrollY 1938). Chrome's scrollY is its layout viewport's, below
// which the visual viewport is: pageTop = scrollY + offsetTop (Galaxy: 1599.3 = 1275.3 + 324).
const scrollYIsVisualTop = ({ scrollY, visual }: ViewportReading) => {
  if (!visual || typeof scrollY !== 'number') return false;
  const { pageTop } = visual;
  return (
    typeof pageTop === 'number' &&
    finite(visual.offsetTop, 0) > 2 &&
    Math.abs(pageTop - scrollY) <= 2
  );
};

// Whether rectangles are relative to a layout viewport taller than what is on the screen (Chrome).
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

// Whether a message is in full view: all of it on the screen, clear of the composer.
export const rectShown = (layout: LayoutReading, rect: Box) => {
  if (visibleArea(layout.viewport).scale !== 1 || !layout.composer)
    return false;
  const bounds = contentBounds(layout);
  return (
    rect.top >= bounds.top &&
    rect.bottom <= Math.min(bounds.bottom, layout.composer.top)
  );
};

// Whether Chrome has brought the visual viewport down onto the keyboard, where it shows the focused composer.
export const viewportRestsOnKeyboard = (viewport: ViewportReading) => {
  const area = visibleArea(viewport);
  return (
    rectsInLayoutViewport(viewport) &&
    area.height < viewport.innerHeight - KEYBOARD_SHRINK_PX &&
    area.top >= viewport.innerHeight - area.height - 2
  );
};

// Whether what is shown has come to rest over the keyboard: Chrome has brought its visual viewport down onto it, or
// Safari, which never reports the keyboard opening, gives rectangles relative to a visual viewport it has shrunk.
const keyboardShown = (viewport: ViewportReading) =>
  rectsInLayoutViewport(viewport)
    ? viewportRestsOnKeyboard(viewport)
    : viewport.rootClientHeight > 0 &&
      visibleArea(viewport).height <
        viewport.rootClientHeight - KEYBOARD_SHRINK_PX;

// How far the composer and the navigation bar are to be raised to sit on the bottom of the visible area.
// Safari keeps fixed and sticky elements on the bottom of its layout viewport, which never goes past the end of the
// page: min(innerHeight, root clientHeight − offsetTop) in on-screen coordinates. While the reader drags up with the
// keyboard open that is innerHeight, below what is shown (iPhone diagnostics: 367 against 287, so 80). When the box is
// focused while reading a little up, Safari scrolls past the end to show it and that bottom is already the visible one
// although innerHeight is larger (iPhone on f35f1ec: 385 against 320.5 raised 64.5 too far; 505 against 287, 218).
// Chrome keeps the layout viewport at the page's height and moves the visual viewport within it, also up when the
// reader drags. While an Android keyboard is opening, Chrome itself moves the visual viewport down to the composer and
// the end of the room with it; raising the composer first would leave the end of the room under the keyboard (Galaxy
// and Pixel on f35f1ec: 323 and 284px). So in Chrome's coordinates nothing is raised until what is shown has rested
// on the keyboard. Safari has by the time it says anything, and a flick with its keyboard open puts innerHeight back
// and offsetTop to 0 for the rest of the inertia, in Chrome's coordinates: the composer still goes on the keyboard
// (iPhone on ddbad17ba3: 262 and 226.5, raised by nothing there).
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
  viewport: ViewportReading;
  // The room scrolls in a box of its own rather than with the page.
  ownScroller: boolean;
  // The first message shown and where it is on the screen, and where a given message is now.
  firstMessage: { id: string; top: number } | null;
  messageTop: (id: string) => number | null;
  // A given message is in full view, clear of the composer.
  messageShown: (id: string) => boolean;
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
  // What is shown has come to rest over the keyboard (see keyboardLift).
  rested: boolean;
}

export interface ScrollState {
  following: boolean;
  target: Target | null;
  // The room was opened at a searched message the page's history entry still names.
  searchEntry: boolean;
  screen: string | null;
  ownJump: boolean;
  // The last jump did not move the page: its original was already shown.
  stillJump: boolean;
  zoomedAway: boolean;
  userScrolling: boolean;
  // A finger is on the screen.
  touching: boolean;
  pendingFollow: boolean;
  // Where the first message was when older ones were about to come in above it.
  anchor: { id: string; top: number } | null;
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
  // The searched message the room was opened at has been reached, or the reader went to the newest: opening the page
  // again is to open it at the newest.
  | { type: 'forgetSearch' }
  // How far to raise the composer and the navigation bar, or null to put back what was there.
  | { type: 'lift'; by: number | null }
  | { type: 'timer'; name: TimerName; delay: number }
  | { type: 'clearTimer'; name: TimerName };

export type ScrollEvent =
  | { type: 'attached' }
  | { type: 'detached' }
  | { type: 'newestShown'; screen: string; mine: boolean }
  | { type: 'targetLoaded'; id: string }
  // movedUp: the page went up to it; moved: the page moved at all (or only the visual viewport did).
  | { type: 'targetScrolled'; id: string; movedUp: boolean; moved: boolean }
  | { type: 'targetMissing' }
  | { type: 'quoteClicked'; id: string }
  | { type: 'jumpToNewest' }
  | { type: 'userIntent'; touch: boolean }
  | { type: 'touch'; down: boolean }
  | { type: 'pageAction' }
  | { type: 'scrolled' }
  | { type: 'viewportScrolled' }
  | { type: 'scrollEnded' }
  | { type: 'composerFocused' }
  | { type: 'composerBlurred' }
  | { type: 'viewportResized' }
  | { type: 'contentResized' }
  | { type: 'olderArriving' }
  | { type: 'olderLoaded' }
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

// Brings the newest message into view. What follows by itself is never done zoomed in, and while the reader is
// scrolling it waits for them to stop: a message that came in is then shown if they are still near the newest. What
// the reader asked for is done at once.
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
  // Scrolling to the end of the page with the keyboard open pulls what is under Safari's toolbar above it.
  const by = s.reveal;
  if (by < 1) return;
  commands.push({ type: 'reveal', by });
  state.echo = { height: s.height };
  commands.push({ type: 'timer', name: 'echoEnd', delay: ECHO_MS });
};

// Soon after a reveal, the visual viewport shrinking by a pixel or two: Safari answering it (iOS diagnostics B 1·2).
// A larger shrink is the keyboard or the page really changing, and is answered.
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
};

// Right after a jump, what the page does with it (the visual viewport moving, or the keyboard going away as the
// quote takes the focus) decides whether the reader is at the newest, exactly as its scroll events do.
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
  // A finger resting on the screen is still the reader's (review f35f D3): what waits keeps waiting.
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
  // Inertia may go on; its scroll events extend this.
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
      // An explicit move (a jump, a button) left nothing to go back to, and with the keyboard gone the reader is at
      // the newest: an original already shown, centred in the shorter view (Android on f35f1ec, 4/4).
      setFollowing(state, true, commands);
      commands.push({ type: 'read', kind: 'return' });
    }
  }
  state.keyboard = null;
  commands.push({ type: 'clearTimer', name: 'keyboardClose' });
  commands.push({ type: 'lift', by: null });
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
      if (state.keyboard) commands.push({ type: 'lift', by: null });
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
      // An original in full view is highlighted where it is: centring it moved an iPhone page by 63px and let go of
      // the newest (ddbad17ba3, S2b). The reader stays where they were, following or not.
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
      // A target still on its way no longer takes the reader anywhere.
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
      if (state.keyboard) state.keyboard.restoreTop = null;
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
      // Safari scrolls by the keyboard from where the page is, and a little up from the newest that leaves its end
      // under the keyboard, beyond what can be scrolled while it is open (iPhone on ddbad17ba3: the last message under
      // the composer by 36~181px). A reader following is shown the newest before it opens, as at the newest.
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
        if (s.distance <= AT_NEWEST_TOLERANCE && !state.target) {
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
      // A toolbar coming back as the reader scrolls is their scroll: it is not undone, then or after.
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

    // Older messages come in above what is being read: the reader's place is kept (rule 5). Browsers do not keep it
    // when the page is at its top, where the button to load them is (review f35f D2: +2,700~3,100px). Following, the
    // content growing keeps the newest in view instead.
    case 'olderArriving':
      state.anchor = state.following ? null : s.firstMessage;
      break;

    case 'olderLoaded': {
      const anchor = state.anchor;
      if (!anchor) break;
      state.anchor = null;
      const top = s.messageTop(anchor.id);
      if (top === null) break;
      const by = top - anchor.top;
      if (Math.abs(by) >= 1) commands.push({ type: 'scrollBy', by });
      break;
    }

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
