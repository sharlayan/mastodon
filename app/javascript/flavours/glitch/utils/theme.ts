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

type ColorScheme = 'auto' | 'light' | 'dark';
type Contrast = 'auto' | 'high';

const colorSchemeMediaWatcher = window.matchMedia(
  '(prefers-color-scheme: dark)',
);
const contrastMediaWatcher = window.matchMedia('(prefers-contrast: more)');

let currentColorScheme: ColorScheme = initialColorScheme;
let currentContrast: Contrast = initialContrast;

const resolveColorScheme = () => {
  const useDarkMode =
    currentColorScheme === 'auto'
      ? colorSchemeMediaWatcher.matches
      : currentColorScheme === 'dark';

  document.documentElement.dataset.colorScheme = useDarkMode ? 'dark' : 'light';
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

export const applyColorScheme = (value: ColorScheme) => {
  currentColorScheme = value;
  resolveColorScheme();
};

export const applyContrast = (value: Contrast) => {
  currentContrast = value;
  resolveContrast();
};
