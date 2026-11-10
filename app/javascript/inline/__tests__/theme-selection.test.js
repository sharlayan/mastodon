describe('inline theme selection', () => {
  const element = document.documentElement;

  beforeEach(() => {
    vi.resetModules();
    vi.stubGlobal('matchMedia', () => ({ matches: false, addEventListener: vi.fn() }));
    element.dataset.colorScheme = 'light';
    element.dataset.contrast = 'auto';
    element.dataset.pageBlogView = 'true';
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    delete element.dataset.pageBlogView;
    delete element.dataset.contrast;
  });

  it('still applies the color scheme and contrast when page storage is blocked', async () => {
    vi.spyOn(window, 'localStorage', 'get').mockImplementation(() => {
      throw new DOMException('Blocked', 'SecurityError');
    });

    await import('../theme-selection');

    expect(element.dataset.colorScheme).toBe('light');
    expect(element.dataset.contrast).toBe('default');
  });
});
