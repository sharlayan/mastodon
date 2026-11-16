import {
  NAVIGATION_PANEL_ITEMS,
  computeNavigationOrder,
  isNavigationItemAlwaysVisible,
} from './items';

describe('Sharlayan navigation registry', () => {
  it('keeps saved order, drops unknown entries, and appends new entries', () => {
    expect(computeNavigationOrder(['bookmarks', 'unknown', 'home'])).toEqual([
      'bookmarks',
      'home',
      ...NAVIGATION_PANEL_ITEMS.filter(
        (key) => key !== 'bookmarks' && key !== 'home',
      ),
    ]);
  });

  it('keeps announcements visible regardless of user hide settings', () => {
    expect(isNavigationItemAlwaysVisible('board_announcements')).toBe(true);
    expect(isNavigationItemAlwaysVisible('home')).toBe(false);
  });
});
