import {
  colorScheme as initialColorScheme,
  contrast as initialContrast,
} from 'flavours/glitch/initial_state';

export function getIsSystemTheme() {
  const { systemTheme } = document.documentElement.dataset;
  return systemTheme === 'true';
}

export function isDarkMode() {
  const { colorScheme } = document.documentElement.dataset;
  return colorScheme === 'dark';
}

export type ColorScheme = 'auto' | 'light' | 'dark';
type Contrast = 'auto' | 'high';

const colorSchemeMediaWatcher = window.matchMedia(
  '(prefers-color-scheme: dark)',
);
const contrastMediaWatcher = window.matchMedia('(prefers-contrast: more)');

let currentColorScheme: ColorScheme = initialColorScheme;
let pageColorScheme: ColorScheme | null = null;
let pageSupportedColorSchemes: ColorScheme[] = ['auto', 'light', 'dark'];
let currentContrast: Contrast = initialContrast;

const resolveColorScheme = () => {
  const useDarkMode =
    (pageColorScheme ?? currentColorScheme) === 'auto'
      ? colorSchemeMediaWatcher.matches
      : (pageColorScheme ?? currentColorScheme) === 'dark';

  document.documentElement.dataset.colorScheme = useDarkMode ? 'dark' : 'light';
  document.documentElement.style.colorScheme = useDarkMode ? 'dark' : 'light';

  document
    .querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')
    .forEach((meta) => {
      meta.content = useDarkMode ? '#181820' : '#ffffff';
    });
};

const resolveContrast = () => {
  const useHighContrast =
    currentContrast === 'high' || contrastMediaWatcher.matches;

  document.documentElement.dataset.contrast = useHighContrast
    ? 'high'
    : 'default';
};

colorSchemeMediaWatcher.addEventListener('change', resolveColorScheme);
contrastMediaWatcher.addEventListener('change', resolveContrast);

export const getColorScheme = (): ColorScheme => currentColorScheme;
export const getContrast = (): Contrast => currentContrast;
export const getSupportedColorSchemes = (): ColorScheme[] => {
  const schemes = document.documentElement.dataset.supportedColorSchemes
    ?.split(' ')
    .filter(
      (scheme): scheme is ColorScheme =>
        scheme === 'auto' || scheme === 'light' || scheme === 'dark',
    );
  return schemes?.length ? schemes : ['auto', 'light', 'dark'];
};

export const applyColorScheme = (value: ColorScheme) => {
  currentColorScheme = value;
  resolveColorScheme();
};

const resolveSupportedColorScheme = (
  value: ColorScheme,
  supported: ColorScheme[],
) => {
  if (supported.includes(value)) return value;
  if (supported.includes('dark') && !supported.includes('light')) return 'dark';
  if (supported.includes('light') && !supported.includes('dark'))
    return 'light';
  return supported[0] ?? 'auto';
};

export const applyPageColorScheme = (
  value: ColorScheme | null,
  supported: ColorScheme[] = pageSupportedColorSchemes,
) => {
  pageSupportedColorSchemes = supported;
  pageColorScheme =
    value === null ? null : resolveSupportedColorScheme(value, supported);
  resolveColorScheme();
};

export const applyContrast = (value: Contrast) => {
  currentContrast = value;
  resolveContrast();
};
