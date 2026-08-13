import { applyUserTheme, containsUnsafeUserThemeValue, decodeUserThemeStorage, encodeUserThemeStorage, parseUserThemeCatalog, portableUserThemeConfig, resolveUserThemeConfig } from '../user_theme';

describe('user theme variables', () => {
  afterEach(() => {
    document.documentElement.removeAttribute('style');
    document.documentElement.dataset.colorScheme = 'dark';
  });

  test('normalizes server themes to the frontend allowlist', () => {
    const catalog = parseUserThemeCatalog(JSON.stringify([{
      id: 'ocean',
      name: 'Ocean',
      variables: { dark: { '--color-bg-primary': '#001122', '--not-allowed': 'red' } },
    }]));

    expect(catalog[0].variables.dark).toEqual({ '--color-bg-primary': '#001122' });
  });

  test('removes resource references and reports unsafe imported values', () => {
    const imported = { dark: { variables: { '--color-bg-primary': 'url(file:///etc/passwd)', '--color-text-primary': '#ffffff' } } };

    expect(containsUnsafeUserThemeValue(imported)).toBe(true);
    expect(resolveUserThemeConfig(imported, {}).dark.variables).toEqual({ '--color-text-primary': '#ffffff' });
  });

  test('round-trips UTF-8 theme JSON through opaque Base64 storage', () => {
    const json = JSON.stringify({ name: '밝은 테마', dark: { theme: '夜' } });

    expect(decodeUserThemeStorage(encodeUserThemeStorage(json))).toBe(json);
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
