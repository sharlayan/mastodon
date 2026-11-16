import { describe, expect, it } from 'vitest';

import {
  isPageBlogViewPath,
  pageBlogThemeNeedsReload,
} from './page_blog_theme';

describe('isPageBlogViewPath', () => {
  it('matches public and owner Page paths for the server-rendered account', () => {
    expect(isPageBlogViewPath('/@alice/pages/example', 'alice')).toBe(true);
    expect(isPageBlogViewPath('/pages/123', 'alice')).toBe(true);
  });

  it('does not match another account', () => {
    expect(isPageBlogViewPath('/@bob/pages/example', 'alice')).toBe(false);
  });
});

describe('pageBlogThemeNeedsReload', () => {
  const state = {
    useBlogView: true,
    pathname: '/@alice/pages/example',
    serverAccount: 'alice',
    skin: 'birdsiteui',
    viewerSkin: 'default',
    stylesheetPresent: true,
  };

  it('keeps a server-rendered Page with its author stylesheet', () => {
    expect(pageBlogThemeNeedsReload(state)).toBe(false);
  });

  it('reloads a Page reached through client-side navigation', () => {
    expect(
      pageBlogThemeNeedsReload({
        ...state,
        serverAccount: undefined,
        stylesheetPresent: false,
      }),
    ).toBe(true);
  });

  it('reloads after the server-rendered author stylesheet was removed', () => {
    expect(
      pageBlogThemeNeedsReload({ ...state, stylesheetPresent: false }),
    ).toBe(true);
  });

  it('does not reload a normal Page layout', () => {
    expect(pageBlogThemeNeedsReload({ ...state, useBlogView: false })).toBe(
      false,
    );
  });
});
