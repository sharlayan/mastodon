export const NAVIGATION_PANEL_ITEMS = [
  'home',
  'explore',
  'federated',
  'local',
  'notifications',
  'favourites',
  'bookmarks',
  'collections',
  'direct',
  'board_announcements',
  'admin_timeline',
] as const;

export type NavigationPanelItem = (typeof NAVIGATION_PANEL_ITEMS)[number];

const ALWAYS_VISIBLE_ITEMS: readonly NavigationPanelItem[] = [
  'board_announcements',
];

export const isNavigationItemAlwaysVisible = (key: string): boolean =>
  (ALWAYS_VISIBLE_ITEMS as readonly string[]).includes(key);

export const navigationPanelItemMessages: Record<
  NavigationPanelItem,
  { id: string; defaultMessage: string }
> = {
  home: { id: 'tabs_bar.home', defaultMessage: 'Home' },
  explore: { id: 'explore.title', defaultMessage: 'Trending' },
  federated: {
    id: 'navigation_bar.public_timeline',
    defaultMessage: 'Federated',
  },
  local: { id: 'navigation_bar.community_timeline', defaultMessage: 'Local' },
  notifications: {
    id: 'tabs_bar.notifications',
    defaultMessage: 'Notifications',
  },
  favourites: { id: 'navigation_bar.favourites', defaultMessage: 'Favorites' },
  bookmarks: { id: 'navigation_bar.bookmarks', defaultMessage: 'Bookmarks' },
  collections: {
    id: 'navigation_bar.collections',
    defaultMessage: 'Collections',
  },
  direct: { id: 'navigation_bar.direct', defaultMessage: 'Private mentions' },
  board_announcements: {
    id: 'navigation_bar.board_announcements',
    defaultMessage: 'Announcements',
  },
  admin_timeline: {
    id: 'navigation_bar.admin_timeline',
    defaultMessage: 'Management timeline',
  },
};

export const computeNavigationOrder = (order?: string[]): string[] => {
  const known = new Set<string>(NAVIGATION_PANEL_ITEMS);
  const result = (order ?? []).filter((key) => known.has(key));

  for (const key of NAVIGATION_PANEL_ITEMS) {
    if (!result.includes(key)) {
      result.push(key);
    }
  }

  return result;
};
