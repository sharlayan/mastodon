import { applyServerBackground } from '../server_background';

describe('applyServerBackground', () => {
  afterEach(() => {
    applyServerBackground();
  });

  it('sets the server background presentation', () => {
    applyServerBackground({
      color: '#102030',
      opacity: 45,
      pathname: '/home',
      url: '/system/site_uploads/files/background.webp',
    });

    expect(
      document.documentElement.classList.contains(
        'sharlayan-server-background',
      ),
    ).toBe(true);
    expect(
      document.documentElement.style.getPropertyValue(
        '--sharlayan-server-background-image',
      ),
    ).toBe('url("/system/site_uploads/files/background.webp")');
    expect(
      document.documentElement.style.getPropertyValue(
        '--sharlayan-server-background-color',
      ),
    ).toBe('#102030');
    expect(
      document.documentElement.style.getPropertyValue(
        '--sharlayan-server-background-opacity',
      ),
    ).toBe('0.45');
  });

  it('removes the background presentation when there is no image or color', () => {
    applyServerBackground({ pathname: '/home', url: '/background.webp' });
    applyServerBackground();

    expect(
      document.documentElement.classList.contains(
        'sharlayan-server-background',
      ),
    ).toBe(false);
    expect(
      document.documentElement.style.getPropertyValue(
        '--sharlayan-server-background-image',
      ),
    ).toBe('');
  });

  it.each([
    '/settings',
    '/settings/preferences/appearance',
    '/admin/settings/custom/appearance',
  ])('does not display the background on settings path %s', (pathname) => {
    applyServerBackground({
      color: '#102030',
      pathname,
      url: '/background.webp',
    });

    expect(
      document.documentElement.classList.contains(
        'sharlayan-server-background',
      ),
    ).toBe(false);
    expect(
      document.documentElement.style.getPropertyValue(
        '--sharlayan-server-background-image',
      ),
    ).toBe('');
  });

  it('allows the background on a settings path when explicitly enabled', () => {
    applyServerBackground({
      pathname: '/admin/settings/custom/appearance',
      showOnSettings: true,
      url: '/background.webp',
    });

    expect(
      document.documentElement.classList.contains(
        'sharlayan-server-background',
      ),
    ).toBe(true);
  });
});
