import { applyUserTheme, BIRDSITEUI_USER_THEME, containsUnsafeUserThemeValue, decodeUserThemeStorage, encodeUserThemeStorage, isSafeUserThemeValue, parseUserThemeCatalog, parseUserThemeOverrides, portableUserThemeConfig, resolveUserThemeConfig, userThemeCatalogForActiveSkin } from '../user_theme';

describe('user theme variables', () => {
  afterEach(() => {
    document.documentElement.removeAttribute('style');
    document.documentElement.dataset.colorScheme = 'dark';
    document.head.querySelectorAll('link[rel~="stylesheet"]').forEach(link => link.remove());
  });

  test('normalizes server themes to the frontend allowlist', () => {
    const catalog = parseUserThemeCatalog(JSON.stringify([{
      id: 'ocean',
      name: 'Ocean',
      variables: { dark: { '--color-bg-primary': '#001122', '--not-allowed': 'red' } },
    }]));

    expect(catalog[0].variables.dark).toEqual({ '--color-bg-primary': '#001122' });
  });

  test('appends the BirdSiteUI preset while preserving server themes', () => {
    const stylesheet = document.createElement('link');
    stylesheet.rel = 'stylesheet';
    stylesheet.href = '/packs-test/skins/glitch/birdsiteui/application.css';
    document.head.appendChild(stylesheet);

    const catalog = userThemeCatalogForActiveSkin([{
      id: 'ocean',
      name: 'Ocean',
      variables: { dark: { '--color-bg-primary': '#001122' } },
    }]);

    expect(catalog.map(theme => theme.id)).toEqual(['ocean', BIRDSITEUI_USER_THEME.id]);
    expect(catalog[1].variables.light['--color-bg-primary']).toBe('#fff');
    expect(catalog[1].variables.dark['--color-bg-primary']).toBe('#1e2028');
  });

  test('does not add the BirdSiteUI preset to other skins', () => {
    const catalog = userThemeCatalogForActiveSkin([]);

    expect(catalog).toEqual([]);
  });

  test('removes resource references and reports unsafe imported values', () => {
    const imported = { dark: { variables: { '--color-bg-primary': 'url(file:///etc/passwd)', '--color-text-primary': '#ffffff' } } };

    expect(containsUnsafeUserThemeValue(imported)).toBe(true);
    expect(resolveUserThemeConfig(imported, {}).dark.variables).toEqual({ '--color-text-primary': '#ffffff' });
  });

  test('accepts spacing and corner lengths while keeping variable-specific validation', () => {
    expect(isSafeUserThemeValue('--space-md', '18px')).toBe(true);
    expect(isSafeUserThemeValue('--radius-sm', '0.5rem')).toBe(true);
    expect(isSafeUserThemeValue('--radius-sm', '-1px')).toBe(false);
    expect(isSafeUserThemeValue('--space-md', '#ffffff')).toBe(false);
    expect(isSafeUserThemeValue('--color-bg-primary', '18px')).toBe(false);
  });

  test('normalizes non-color theme variables', () => {
    const config = resolveUserThemeConfig({ dark: { variables: { '--space-md': '18px', '--radius-sm': '0.5rem' } } }, {});

    expect(config.dark.variables).toEqual({ '--space-md': '18px', '--radius-sm': '0.5rem' });
  });

  test('stores UTF-8 theme JSON without Base64 encoding', () => {
    const json = JSON.stringify({ name: '밝은 테마', dark: { theme: '夜' } });

    expect(encodeUserThemeStorage(json)).toBe(json);
  });

  test('reads legacy plain JSON storage values', () => {
    expect(resolveUserThemeConfig('{"dark":{"theme":"legacy"}}', {}).dark.theme).toBe('legacy');
  });

  test('layers user variables over the selected server theme', () => {
    document.documentElement.dataset.colorScheme = 'dark';
    const catalog = parseUserThemeCatalog([{
      id: 'ocean',
      name: 'Ocean',
      variables: { dark: { '--color-bg-primary': '#001122', '--color-text-primary': '#ffffff' } },
    }]);
    const config = resolveUserThemeConfig({ dark: { theme: 'ocean', variables: { '--color-bg-primary': '#112233' } } }, {});

    applyUserTheme(config, catalog);

    expect(document.documentElement.style.getPropertyValue('--color-bg-primary')).toBe('#112233');
    expect(document.documentElement.style.getPropertyValue('--color-text-primary')).toBe('#ffffff');
  });

  test('keeps separate light and dark selections', () => {
    const config = resolveUserThemeConfig({
      light: { variables: { '--color-bg-primary': '#ffffff' } },
      dark: { variables: { '--color-bg-primary': '#000000' } },
    }, {});

    document.documentElement.dataset.colorScheme = 'light';
    applyUserTheme(config, []);
    expect(document.documentElement.style.getPropertyValue('--color-bg-primary')).toBe('#ffffff');

    document.documentElement.dataset.colorScheme = 'dark';
    applyUserTheme(config, []);
    expect(document.documentElement.style.getPropertyValue('--color-bg-primary')).toBe('#000000');
  });

  test('uses server defaults until the user overrides them', () => {
    const config = resolveUserThemeConfig({}, { dark: { theme: 'server-dark', variables: { '--color-bg-primary': '#101010' } } });

    expect(config.dark).toEqual({ theme: 'server-dark', variables: { '--color-bg-primary': '#101010' } });
  });

  test('keeps user overrides separate when server defaults change', () => {
    const overrides = parseUserThemeOverrides({ dark: { variables: { '--color-text-primary': '#ffffff' } } });
    const config = resolveUserThemeConfig(overrides, { dark: { theme: 'new-default', variables: { '--color-bg-primary': '#202020' } } });

    expect(overrides.dark).toEqual({ variables: { '--color-text-primary': '#ffffff' } });
    expect(config.dark).toEqual({ theme: 'new-default', variables: { '--color-bg-primary': '#202020', '--color-text-primary': '#ffffff' } });
  });

  test('removes stored overrides when the server disables user themes', () => {
    document.documentElement.style.setProperty('--color-bg-primary', '#001122');

    applyUserTheme({}, [], false);

    expect(document.documentElement.style.getPropertyValue('--color-bg-primary')).toBe('');
  });

  test('exports selected server theme values as portable overrides', () => {
    const catalog = parseUserThemeCatalog([{
      id: 'ocean',
      name: 'Ocean',
      variables: { dark: { '--color-bg-primary': '#001122' } },
    }]);
    const config = resolveUserThemeConfig({ dark: { theme: 'ocean', variables: { '--color-text-primary': '#ffffff' } } }, {});

    expect(portableUserThemeConfig(config, catalog).dark).toEqual({
      theme: 'default',
      variables: {
        '--color-bg-primary': '#001122',
        '--color-text-primary': '#ffffff',
      },
    });
  });
});
