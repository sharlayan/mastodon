import { useCallback } from 'react';

import { useRouteMatch, useLocation } from 'react-router-dom';

const PUBLIC_TIMELINE_PATHS = ['/public', '/public/local'];

// Public/local timeline links must stay mutually exclusive: react-router's
// default prefix matching keeps `/public` active while on `/public/local`, so
// Sharlayan compares the exact pathname instead. `match` drives the active icon
// and `isActive` (when defined) overrides NavLink's own matching.
export function useSharlayanColumnLinkActive(
  to: string | { pathname?: string } | undefined,
): { match: unknown; isActive?: () => boolean } {
  const location = useLocation();
  const toPath = (typeof to === 'string' ? to : to?.pathname) ?? '';
  const routeMatch = useRouteMatch(toPath);
  const isPublicTimeline = PUBLIC_TIMELINE_PATHS.includes(toPath);

  const navLinkIsActive = useCallback(
    () => location.pathname === toPath,
    [location.pathname, toPath],
  );

  return {
    match: isPublicTimeline ? location.pathname === toPath : routeMatch,
    isActive: isPublicTimeline ? navLinkIsActive : undefined,
  };
}
