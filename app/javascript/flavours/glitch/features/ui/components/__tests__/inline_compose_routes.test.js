import {
  isInlineComposeFeedRoute,
  normalizeInlineComposePath,
} from '../inline_compose_routes';

describe('inline compose routes', () => {
  it('normalizes mobile advanced-interface paths', () => {
    expect(
      ['/deck/home', '/deck/public/local', '/deck/lists/123'].map(normalizeInlineComposePath),
    ).toEqual(['/home', '/public/local', '/lists/123']);
  });

  it('recognizes mobile advanced-interface feeds', () => {
    const paths = [
      '/deck/home',
      '/deck/public/local',
      '/deck/public',
      '/deck/lists/123',
      '/deck/antennas/456',
      '/deck/timelines/direct',
    ];

    expect(paths.filter((pathname) => !isInlineComposeFeedRoute(pathname))).toEqual([]);
  });

  it('does not treat a non-feed advanced-interface route as a feed', () => {
    expect(isInlineComposeFeedRoute('/deck/notifications')).toBe(false);
  });

  it('recognizes a saved custom tab path', () => {
    expect(isInlineComposeFeedRoute('/deck/custom-feed', ['/custom-feed'])).toBe(true);
  });
});
