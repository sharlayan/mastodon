import {
  shouldExitDetailedForInlineCompose,
  shouldNavigateToComposePage,
  shouldOpenInlineComposeDirectModal,
  shouldOpenInlineComposeReplyModal,
} from '../inline_reply_navigation';

describe('inline compose reply navigation', () => {
  it.each([
    '/@alice/123',
    '/@alice@example.com/123',
    '/statuses/123',
  ])('exits a detailed status route in single-column mode: %s', (pathname) => {
    expect(shouldExitDetailedForInlineCompose({
      enabled: true,
      layout: 'single-column',
      pathname,
    })).toBe(true);
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

  it.each([
    '/home',
    '/public',
    '/public/local',
    '/lists/123',
    '/antennas/123',
    '/conversations',
    '/timelines/direct',
  ])('uses the reply popup on an inline-compose feed: %s', (pathname) => {
    expect(shouldOpenInlineComposeReplyModal({
      disablePopup: false,
      enabled: true,
      layout: 'single-column',
      pathname,
    })).toBe(true);
  });

  it('keeps timeline replies in the inline compose box when the popup is disabled', () => {
    expect(shouldOpenInlineComposeReplyModal({
      disablePopup: true,
      enabled: true,
      layout: 'single-column',
      pathname: '/home',
    })).toBe(false);
  });

  it.each([
    '/home',
    '/@alice/123',
  ])('navigates to the compose page when the popup is disabled on mobile: %s', (pathname) => {
    expect(shouldNavigateToComposePage({
      disableMobilePopup: true,
      enabled: true,
      layout: 'mobile',
      pathname,
    })).toBe(true);
  });

  it('keeps the inline compose box when the popup is disabled on desktop single-column layout', () => {
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
