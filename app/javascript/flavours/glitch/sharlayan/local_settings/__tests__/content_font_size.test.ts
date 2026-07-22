import { applyContentFontSize } from '../content_font_size';

describe('applyContentFontSize', () => {
  afterEach(() => {
    document.documentElement.className = '';
  });

  it('sets a single class for non-default sizes', () => {
    applyContentFontSize('x_large');

    expect(document.documentElement.className).toBe(
      'content-font-size__x_large',
    );
  });

  it('replaces a previously applied size', () => {
    applyContentFontSize('large');
    applyContentFontSize('xx_large');

    expect(document.documentElement.className).toBe(
      'content-font-size__xx_large',
    );
  });

  it('clears the class for the default size and unknown values', () => {
    applyContentFontSize('large');
    applyContentFontSize('medium');

    expect(document.documentElement.className).toBe('');

    applyContentFontSize('large');
    applyContentFontSize(undefined);

    expect(document.documentElement.className).toBe('');
  });
});
