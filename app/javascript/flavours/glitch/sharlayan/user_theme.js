export const USER_THEME_VARIABLES = [
  '--color-text-primary',
  '--color-text-secondary',
  '--color-text-brand',
  '--color-bg-primary',
  '--color-bg-secondary',
  '--color-bg-tertiary',
  '--color-bg-brand-base',
  '--color-bg-brand-soft',
  '--color-bg-brand-softest',
  '--color-border-primary',
  '--color-border-strong',
  '--color-border-brand',
];

const SCHEMES = ['light', 'dark'];
const VARIABLE_SET = new Set(USER_THEME_VARIABLES);
const REFERENCE_FUNCTION = /(?:url|src|image-set|cross-fade|element|paint|var|env)\s*\(/i;

export const encodeUserThemeStorage = (value) => {
  const bytes = new TextEncoder().encode(typeof value === 'string' ? value : JSON.stringify(value));
  let binary = '';
  bytes.forEach(byte => { binary += String.fromCharCode(byte); });
  return window.btoa(binary);
};

export const decodeUserThemeStorage = (value) => {
  if (typeof value !== 'string' || value.length === 0) return '{}';
  if (value.trimStart().startsWith('{')) return value;

  try {
    const binary = window.atob(value);
    const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  } catch {
    return '{}';
  }
};

export const isSafeUserThemeValue = (value) => {
  if (typeof value !== 'string' || value.length > 256 || REFERENCE_FUNCTION.test(value)) return false;
  if (typeof CSS !== 'undefined' && typeof CSS.supports === 'function') return CSS.supports('color', value);
  return true;
};

export const containsUnsafeUserThemeValue = (value) => {
  const parsed = parseObject(value);
  return SCHEMES.some(scheme => Object.values(parseObject(parsed[scheme]?.variables)).some(candidate => !isSafeUserThemeValue(candidate)));
};

const parseObject = (value) => {
  try {
    const parsed = typeof value === 'string' ? JSON.parse(value) : value;
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
};

const normalizeVariables = (variables) => Object.fromEntries(
  Object.entries(parseObject(variables)).filter(([name, value]) => VARIABLE_SET.has(name) && isSafeUserThemeValue(value)),
);

const normalizeScheme = (scheme) => {
  const parsed = parseObject(scheme);
  return {
    theme: typeof parsed.theme === 'string' ? parsed.theme : 'default',
    variables: normalizeVariables(parsed.variables),
  };
};

export const parseUserThemeCatalog = (value) => {
  try {
    const parsed = typeof value === 'string' ? JSON.parse(value) : value;
    if (!Array.isArray(parsed)) return [];

    return parsed.filter(theme => theme && typeof theme.id === 'string' && typeof theme.name === 'string').map(theme => ({
      id: theme.id,
      name: theme.name,
      variables: {
        light: normalizeVariables(theme.variables?.light),
        dark: normalizeVariables(theme.variables?.dark),
      },
    }));
  } catch {
    return [];
  }
};

export const resolveUserThemeConfig = (userValue, defaultValue) => {
  const user = parseObject(typeof userValue === 'string' ? decodeUserThemeStorage(userValue) : userValue);
  const defaults = parseObject(defaultValue);

  return Object.fromEntries(SCHEMES.map(scheme => [
    scheme,
    normalizeScheme(user[scheme] ?? defaults[scheme]),
  ]));
};

export const portableUserThemeConfig = (config, catalog) => Object.fromEntries(SCHEMES.map(scheme => {
  const selected = normalizeScheme(config?.[scheme]);
  const theme = catalog.find(candidate => candidate.id === selected.theme);
  return [scheme, {
    theme: 'default',
    variables: { ...(theme?.variables?.[scheme] ?? {}), ...selected.variables },
  }];
}));

export const applyUserTheme = (config, catalog, enabled = true) => {
  const root = document.documentElement;
  USER_THEME_VARIABLES.forEach(variable => root.style.removeProperty(variable));
  if (!enabled) return;

  const scheme = root.dataset.colorScheme === 'light' ? 'light' : 'dark';
  const selected = normalizeScheme(config?.[scheme]);
  const theme = catalog.find(candidate => candidate.id === selected.theme);
  const variables = { ...(theme?.variables?.[scheme] ?? {}), ...selected.variables };

  Object.entries(variables).forEach(([name, value]) => {
    if (VARIABLE_SET.has(name)) root.style.setProperty(name, value);
  });
};

let colorSchemeObserver;

export const watchUserTheme = (config, catalog, enabled = true) => {
  colorSchemeObserver?.disconnect();
  applyUserTheme(config, catalog, enabled);
  colorSchemeObserver = new MutationObserver(() => applyUserTheme(config, catalog, enabled));
  colorSchemeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-color-scheme'] });
};
