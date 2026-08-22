import { matchPath } from 'react-router-dom';

const feedRoutePatterns = [
  '/home',
  '/timelines/home',
  '/public/local',
  '/timelines/public/local',
  '/public',
  '/timelines/public',
  '/lists/:id',
  '/antennas/:id',
  '/timelines/antenna/:id',
  '/timelines/direct',
];

export const normalizeInlineComposePath = (pathname) =>
  pathname.startsWith('/deck/') ? pathname.slice(5) : pathname;

export const isInlineComposeFeedRoute = (pathname, tabPaths = []) => {
  const normalizedPath = normalizeInlineComposePath(pathname);
  const patterns = feedRoutePatterns.concat(tabPaths);

  return patterns.some((path) =>
    matchPath(normalizedPath, { path, exact: true }),
  );
};
