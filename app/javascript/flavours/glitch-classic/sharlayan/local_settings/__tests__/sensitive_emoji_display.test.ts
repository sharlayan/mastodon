import { applySensitiveEmojiDisplay } from '../sensitive_emoji_display';

describe('applySensitiveEmojiDisplay', () => {
  afterEach(() => {
    document.documentElement.className = '';
  });

  it('sets exactly one display mode class', () => {
    applySensitiveEmojiDisplay('grayscale');
    applySensitiveEmojiDisplay('hide');

    expect(document.documentElement.className).toBe(
      'sensitive-emoji-display--hide',
    );
  });

  it('falls back to showing sensitive emoji for unknown values', () => {
    applySensitiveEmojiDisplay('hide');
    applySensitiveEmojiDisplay(undefined);

    expect(document.documentElement.className).toBe(
      'sensitive-emoji-display--show',
    );
  });
});
