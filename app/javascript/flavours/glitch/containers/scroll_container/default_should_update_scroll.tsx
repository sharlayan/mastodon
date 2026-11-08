import type { ShouldUpdateScroll } from 'scroll-behavior';

import type { MastodonLocation } from 'flavours/glitch/components/router';

export type ShouldUpdateScrollFn = ShouldUpdateScroll<MastodonLocation>;

/**
 * ScrollBehavior will automatically scroll to the top on navigations
 * or restore saved scroll positions, but on some location changes we
 * need to prevent this.
 */

const CHAT_SCREEN = /^\/chat(\/|$)/;

const searchedMessage = (location: MastodonLocation | null) =>
  (location?.state as { chatMessageId?: unknown } | null | undefined)
    ?.chatMessageId;

export const defaultShouldUpdateScroll: ShouldUpdateScrollFn = (
  prevLocation,
  location,
) => {
  // If the change is caused by opening a modal, do not scroll to top
  const shouldUpdateScroll = !(
    location.state?.mastodonModalKey &&
    location.state.mastodonModalKey !== prevLocation?.state?.mastodonModalKey
  );

  // A chat screen fetches what it shows only after this runs, so a saved position would be cut short by the height
  // of an empty page, which on a phone is just enough to hide the tabs. A page load has no location key either, so
  // what it would restore may be left over from another page. A room then scrolls to its newest message by itself.
  // A room drops the searched message it was opened at from its history entry once it is done with it; the reader
  // stays where they are.
  if (
    prevLocation &&
    CHAT_SCREEN.test(location.pathname) &&
    prevLocation.pathname === location.pathname &&
    prevLocation.search === location.search &&
    searchedMessage(prevLocation) !== undefined &&
    searchedMessage(location) === undefined
  )
    return false;

  if (
    shouldUpdateScroll &&
    (prevLocation
      ? location.pathname === '/chat' &&
        prevLocation.pathname !== location.pathname
      : CHAT_SCREEN.test(location.pathname))
  )
    return [0, 0];

  return shouldUpdateScroll;
};
