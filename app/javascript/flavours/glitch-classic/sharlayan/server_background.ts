interface ServerBackgroundOptions {
  color?: string;
  opacity?: number;
  pathname?: string;
  showOnSettings?: boolean;
  url?: string;
}

export const isSettingsPath = (pathname: string) =>
  pathname === '/settings' ||
  pathname.startsWith('/settings/') ||
  pathname === '/admin/settings' ||
  pathname.startsWith('/admin/settings/');

export const applyServerBackground = ({
  color,
  opacity = 100,
  pathname = window.location.pathname,
  showOnSettings = false,
  url,
}: ServerBackgroundOptions = {}) => {
  const root = document.documentElement;
  const enabled =
    (!isSettingsPath(pathname) || showOnSettings) &&
    (Boolean(url) || Boolean(color));

  root.classList.toggle('sharlayan-server-background', enabled);

  if (enabled && url) {
    root.style.setProperty(
      '--sharlayan-server-background-image',
      `url(${JSON.stringify(url)})`,
    );
  } else {
    root.style.removeProperty('--sharlayan-server-background-image');
  }

  if (enabled && color) {
    root.style.setProperty('--sharlayan-server-background-color', color);
  } else {
    root.style.removeProperty('--sharlayan-server-background-color');
  }

  if (enabled) {
    root.style.setProperty(
      '--sharlayan-server-background-opacity',
      String(Math.min(100, Math.max(0, opacity)) / 100),
    );
  } else {
    root.style.removeProperty('--sharlayan-server-background-opacity');
  }
};
