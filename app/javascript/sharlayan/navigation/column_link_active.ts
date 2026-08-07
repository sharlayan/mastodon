import { useCallback } from 'react';

import { useRouteMatch, useLocation } from 'react-router-dom';

const PUBLIC_TIMELINE_PATHS = ['/public', '/public/local'];

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
