import {
  shouldExitDetailedForInlineCompose,
  shouldNavigateToComposePage,
  shouldOpenInlineComposeDirectModal,
  shouldOpenInlineComposeReplyModal,
} from '../inline_reply_navigation';

describe('inline compose reply navigation', () => {
  it('exits detailed status routes in single-column mode', () => {
    const paths = ['/@alice/123', '/@alice@example.com/123', '/statuses/123'];

    expect(paths.filter((pathname) => !shouldExitDetailedForInlineCompose({
      enabled: true,
      layout: 'single-column',
      pathname,
    }))).toEqual([]);
  });

  it('does not exit in multi-column mode', () => {
    expect(shouldExitDetailedForInlineCompose({
      enabled: true,
      layout: 'multi-column',
      pathname: '/deck/@alice/123',
    })).toBe(false);
  });

  it('does not exit when inline compose is disabled or the route is not detailed', () => {
    expect(shouldExitDetailedForInlineCompose({
      enabled: false,
      layout: 'single-column',
      pathname: '/@alice/123',
    })).toBe(false);
    expect(shouldExitDetailedForInlineCompose({
      enabled: true,
      layout: 'single-column',
      pathname: '/home',
    })).toBe(false);
  });

  it('uses the reply popup by default and allows opting out', () => {
    const options = {
      enabled: true,
      layout: 'single-column',
      pathname: '/@alice/123',
    };

    expect(shouldOpenInlineComposeReplyModal({
      ...options,
      disablePopup: false,
    })).toBe(true);
    expect(shouldOpenInlineComposeReplyModal({
      ...options,
      disablePopup: true,
    })).toBe(false);
  });

  it('uses the reply popup on inline-compose feeds and keeps timeline replies inline when the popup is disabled', () => {
    const paths = [
      '/home',
      '/public',
      '/public/local',
      '/lists/123',
      '/antennas/123',
      '/conversations',
      '/timelines/direct',
    ];

    expect(paths.filter((pathname) => !shouldOpenInlineComposeReplyModal({
      disablePopup: false,
      enabled: true,
      layout: 'single-column',
      pathname,
    }))).toEqual([]);
    expect(shouldOpenInlineComposeReplyModal({
      disablePopup: true,
      enabled: true,
      layout: 'single-column',
      pathname: '/home',
    })).toBe(false);
  });

  it('applies reply navigation preferences on the supported feed aliases', () => {
    const paths = [
      '/deck/home',
      '/deck/public/local',
      '/deck/timelines/antenna/123',
      '/timelines/home',
      '/timelines/public',
      '/timelines/public/local',
      '/timelines/antenna/123',
      '/deck/conversations',
    ];

    expect(paths.map((pathname) => {
      const options = { enabled: true, layout: 'mobile', pathname };

      return [
        pathname,
        shouldNavigateToComposePage({ ...options, disableMobilePopup: true }),
        shouldOpenInlineComposeReplyModal({ ...options, disableMobilePopup: false }),
        shouldOpenInlineComposeReplyModal({ ...options, layout: 'single-column', disablePopup: false }),
      ];
    })).toEqual(paths.map((pathname) => [pathname, true, true, true]));
  });

  it('preserves the conversation list exception without treating a conversation thread as an inline feed', () => {
    const options = { enabled: true, layout: 'single-column', disablePopup: false };

    expect(shouldOpenInlineComposeReplyModal({ ...options, pathname: '/conversations' })).toBe(true);
    expect(shouldOpenInlineComposeReplyModal({ ...options, pathname: '/conversations/123' })).toBe(false);
  });

  it('navigates to the compose page when the popup is disabled on mobile but keeps the inline box on desktop single-column layout', () => {
    expect(['/home', '/@alice/123'].map((pathname) => shouldNavigateToComposePage({
      disableMobilePopup: true,
      enabled: true,
      layout: 'mobile',
      pathname,
    }))).toEqual([true, true]);
    expect(shouldNavigateToComposePage({
      disableMobilePopup: true,
      enabled: true,
      layout: 'single-column',
      pathname: '/home',
    })).toBe(false);
  });

  it('allows using the reply popup on mobile independently of the desktop setting', () => {
    expect(shouldOpenInlineComposeReplyModal({
      disableMobilePopup: false,
      disablePopup: true,
      enabled: true,
      layout: 'mobile',
      pathname: '/home',
    })).toBe(true);
  });

  it('does not use the popup on feeds without an active single-column inline compose box', () => {
    expect(shouldOpenInlineComposeReplyModal({
      disablePopup: false,
      enabled: false,
      layout: 'single-column',
      pathname: '/home',
    })).toBe(false);
    expect(shouldOpenInlineComposeReplyModal({
      disablePopup: false,
      enabled: true,
      layout: 'multi-column',
      pathname: '/home',
    })).toBe(false);
    expect(shouldOpenInlineComposeReplyModal({
      disablePopup: false,
      enabled: true,
      layout: 'single-column',
      pathname: '/explore',
    })).toBe(false);
  });

  it('uses the direct-message popup whenever inline compose is enabled in single-column mode', () => {
    expect(shouldOpenInlineComposeDirectModal({
      enabled: true,
      layout: 'single-column',
    })).toBe(true);
    expect(shouldOpenInlineComposeDirectModal({
      enabled: false,
      layout: 'single-column',
    })).toBe(false);
    expect(shouldOpenInlineComposeDirectModal({
      enabled: true,
      layout: 'multi-column',
    })).toBe(false);
  });
});
