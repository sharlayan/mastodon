interface PageBlogThemeState {
  useBlogView: boolean;
  pathname: string;
  serverAccount?: string | null;
  skin?: string | null;
  viewerSkin?: string | null;
  stylesheetPresent: boolean;
}

export const isPageBlogViewPath = (
  pathname: string,
  serverAccount?: string | null,
): boolean =>
  Boolean(
    serverAccount &&
    (pathname === `/@${serverAccount}/pages` ||
      pathname.startsWith(`/@${serverAccount}/pages/`) ||
      /^\/pages(?:\/[0-9]+(?:\/edit)?|\/new)$/.test(pathname)),
  );

export const pageBlogThemeNeedsReload = ({
  useBlogView,
  pathname,
  serverAccount,
  skin,
  viewerSkin,
  stylesheetPresent,
}: PageBlogThemeState): boolean => {
  if (!useBlogView) {
    return false;
  }

  if (!isPageBlogViewPath(pathname, serverAccount)) {
    return true;
  }

  return Boolean(skin && skin !== viewerSkin && !stylesheetPresent);
};
