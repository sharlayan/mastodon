(function (element) {
  const {colorScheme, contrast} = element.dataset;
  const supportedColorSchemes = (element.dataset.supportedColorSchemes || 'auto light dark').split(' ');
  const pageColorScheme = element.dataset.pageBlogView === 'true'
    ? window.localStorage.getItem('mastodon-page-color-scheme')
    : null;
  const requestedColorScheme = pageColorScheme || colorScheme;
  const effectiveColorScheme = supportedColorSchemes.includes(requestedColorScheme)
    ? requestedColorScheme
    : supportedColorSchemes.includes('dark') && !supportedColorSchemes.includes('light')
      ? 'dark'
      : supportedColorSchemes.includes('light') && !supportedColorSchemes.includes('dark')
        ? 'light'
        : supportedColorSchemes[0] || 'auto';

  const colorSchemeMediaWatcher = window.matchMedia('(prefers-color-scheme: dark)');
  const contrastMediaWatcher = window.matchMedia('(prefers-contrast: more)');

  const updateColorScheme = () => {
    const useDarkMode = effectiveColorScheme === 'auto' ? colorSchemeMediaWatcher.matches : effectiveColorScheme === 'dark';

    element.dataset.colorScheme = useDarkMode ? 'dark' : 'light';
  };

  const updateContrast = () => {
    const useHighContrast = contrast === 'high' || contrastMediaWatcher.matches;

    element.dataset.contrast = useHighContrast ? 'high' : 'default';
  }

  colorSchemeMediaWatcher.addEventListener('change', updateColorScheme);
  contrastMediaWatcher.addEventListener('change', updateContrast);

  updateColorScheme();
  updateContrast();

  const isRedesignEnabled = (
    window.localStorage.getItem('experiments')?.split(',') ?? []
  ).includes('redesign');

  if (isRedesignEnabled) {
    element.dataset.redesign = true;
  }

})(document.documentElement);
