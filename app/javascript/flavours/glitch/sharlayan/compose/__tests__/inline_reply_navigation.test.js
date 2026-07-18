import { shouldExitDetailedForInlineCompose } from '../inline_reply_navigation';

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
});
