export const USER_THEME_VARIABLE_GROUPS = [
  {
    id: 'text',
    variables: [
      { name: '--color-text-primary', type: 'color' },
      { name: '--color-text-secondary', type: 'color' },
      { name: '--color-text-brand', type: 'color' },
    ],
  },
  {
    id: 'backgrounds',
    variables: [
      { name: '--color-bg-primary', type: 'color' },
      { name: '--color-bg-secondary', type: 'color' },
      { name: '--color-bg-tertiary', type: 'color' },
      { name: '--color-bg-brand-base', type: 'color' },
      { name: '--color-bg-brand-soft', type: 'color' },
      { name: '--color-bg-brand-softest', type: 'color' },
    ],
  },
  {
    id: 'borders',
    variables: [
      { name: '--color-border-primary', type: 'color' },
      { name: '--color-border-strong', type: 'color' },
      { name: '--color-border-brand', type: 'color' },
    ],
  },
  {
    id: 'spacing',
    variables: [
      { name: '--space-3xs', type: 'length' },
      { name: '--space-2xs', type: 'length' },
      { name: '--space-xs', type: 'length' },
      { name: '--space-sm', type: 'length' },
      { name: '--space-md', type: 'length' },
      { name: '--space-lg', type: 'length' },
      { name: '--space-xl', type: 'length' },
      { name: '--space-2xl', type: 'length' },
      { name: '--space-3xl', type: 'length' },
      { name: '--space-4xl', type: 'length' },
      { name: '--space-5xl', type: 'length' },
    ],
  },
  {
    id: 'corners',
    variables: [
      { name: '--radius-xs', type: 'length' },
      { name: '--radius-sm', type: 'length' },
      { name: '--radius-md', type: 'length' },
      { name: '--radius-lg', type: 'length' },
      { name: '--radius-xl', type: 'length' },
    ],
  },
];

export const USER_THEME_VARIABLES = USER_THEME_VARIABLE_GROUPS.flatMap(group => group.variables.map(variable => variable.name));

const SCHEMES = ['light', 'dark'];
const VARIABLE_SET = new Set(USER_THEME_VARIABLES);
const VARIABLE_TYPES = new Map(USER_THEME_VARIABLE_GROUPS.flatMap(group => group.variables.map(variable => [variable.name, variable.type])));
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

export const isSafeUserThemeValue = (variable, value) => {
  if (typeof value !== 'string' || value.length > 256 || REFERENCE_FUNCTION.test(value)) return false;
  const type = VARIABLE_TYPES.get(variable);
  if (!type) return false;
  if (typeof CSS !== 'undefined' && typeof CSS.supports === 'function') {
    const property = type === 'color' ? 'color' : variable.startsWith('--radius-') ? 'border-radius' : 'margin';
    return CSS.supports(property, value);
  }
  return true;
};

export const containsUnsafeUserThemeValue = (value) => {
  const parsed = parseObject(value);
  return SCHEMES.some(scheme => Object.entries(parseObject(parsed[scheme]?.variables)).some(([name, candidate]) => VARIABLE_SET.has(name) && !isSafeUserThemeValue(name, candidate)));
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
  Object.entries(parseObject(variables)).filter(([name, value]) => VARIABLE_SET.has(name) && isSafeUserThemeValue(name, value)),
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
