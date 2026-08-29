import {
  isInlineComposeFeedRoute,
  normalizeInlineComposePath,
} from '../inline_compose_routes';

describe('inline compose routes', () => {
  it.each([
    ['/deck/home', '/home'],
    ['/deck/public/local', '/public/local'],
    ['/deck/lists/123', '/lists/123'],
  ])('normalizes the mobile advanced-interface path %s', (pathname, expected) => {
    expect(normalizeInlineComposePath(pathname)).toBe(expected);
  });

  it.each([
    '/deck/home',
    '/deck/public/local',
    '/deck/public',
    '/deck/lists/123',
    '/deck/antennas/456',
    '/deck/timelines/direct',
  ])('recognizes %s as a mobile advanced-interface feed', (pathname) => {
    expect(isInlineComposeFeedRoute(pathname)).toBe(true);
  });

  it('does not treat a non-feed advanced-interface route as a feed', () => {
    expect(isInlineComposeFeedRoute('/deck/notifications')).toBe(false);
  });

  it('recognizes a saved custom tab path', () => {
    expect(isInlineComposeFeedRoute('/deck/custom-feed', ['/custom-feed'])).toBe(true);
  });
});
