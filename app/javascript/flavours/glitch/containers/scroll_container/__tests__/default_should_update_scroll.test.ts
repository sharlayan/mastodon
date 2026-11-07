import type { MastodonLocation } from 'flavours/glitch/components/router';

import { defaultShouldUpdateScroll } from '../default_should_update_scroll';

const at = (pathname: string, extra: Partial<MastodonLocation> = {}) =>
  ({
    pathname,
    search: '',
    hash: '',
    state: undefined,
    ...extra,
  }) as MastodonLocation;

const update = (prev: MastodonLocation | null, next: MastodonLocation) =>
  defaultShouldUpdateScroll.call(
    {} as never,
    prev as never,
    next as never,
  ) as unknown;

describe('defaultShouldUpdateScroll', () => {
  describe('when a chat screen is loaded', () => {
    it.each(['/chat', '/chat/new', '/chat/123', '/chat/123/members'])(
      'starts %s at the top, whatever an earlier load in this tab saved',
      (pathname) => {
        expect(update(null, at(pathname))).toEqual([0, 0]);
      },
    );

    it('starts at the top when reloading a location that has its own key too', () => {
      expect(update(null, at('/chat', { key: 'abc' }))).toEqual([0, 0]);
    });
  });

  describe('arriving at the conversation list inside the app', () => {
    it.each(['/chat/123', '/chat/new', '/home'])(
      'starts at the top coming from %s, since the list is fetched again',
      (pathname) => {
        expect(update(at(pathname), at('/chat', { key: 'abc' }))).toEqual([
          0, 0,
        ]);
      },
    );

    it('stays where it is when a modal opens on the list', () => {
      expect(
        update(at('/chat'), at('/chat', { state: { mastodonModalKey: 'a' } })),
      ).toBe(false);
    });

    it('goes back to where it was when that modal closes', () => {
      expect(
        update(
          at('/chat', { state: { mastodonModalKey: 'a' } }),
          at('/chat', { key: 'abc' }),
        ),
      ).toBe(true);
    });
  });

  describe('a room forgetting the searched message it was opened at', () => {
    it('stays where the reader is when only that leaves its history entry', () => {
      expect(
        update(
          at('/chat/123', {
            key: 'abc',
            state: { fromMastodon: true, chatMessageId: '343' } as never,
          }),
          at('/chat/123', { key: 'def', state: { fromMastodon: true } }),
        ),
      ).toBe(false);
    });

    it('leaves opening a room at a searched message to the usual rules', () => {
      expect(
        update(
          at('/chat'),
          at('/chat/123', {
            key: 'def',
            state: { fromMastodon: true, chatMessageId: '343' } as never,
          }),
        ),
      ).toBe(true);
    });
  });

  describe('moving to other chat screens inside the app', () => {
    it.each(['/chat/123', '/chat/123/members', '/chat/new'])(
      'leaves %s to the usual rules',
      (pathname) => {
        expect(update(at('/chat'), at(pathname, { key: 'def' }))).toBe(true);
      },
    );
  });

  describe('other screens', () => {
    it.each(['/home', '/notifications', '/chatter', '/@chat', '/lists/chat'])(
      'leaves a load of %s to the usual rules',
      (pathname) => {
        expect(update(null, at(pathname))).toBe(true);
      },
    );

    it('still does not scroll when a modal opens', () => {
      expect(
        update(
          at('/home'),
          at('/home', { state: { mastodonModalKey: 'modal' } }),
        ),
      ).toBe(false);
    });
  });
});
