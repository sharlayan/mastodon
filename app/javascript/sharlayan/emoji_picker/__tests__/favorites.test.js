import { describe, expect, it } from 'vitest';

import {
  emojiPickerFavoriteProps,
  emojiPickerFavoritesCategoryLabel,
  shouldIgnoreEmojiDropdownClose,
} from '../favorites';

const intl = { formatMessage: (message) => message.id };

describe('emojiPickerFavoritesCategoryLabel', () => {
  it('resolves the favorites category message', () => {
    expect(emojiPickerFavoritesCategoryLabel(intl)).toBe(
      'emoji_button.favorites',
    );
  });
});

describe('emojiPickerFavoriteProps', () => {
  it('passes through the favorite emojis and callbacks', () => {
    const favoriteEmojis = ['a'];
    const onAddFavorite = () => undefined;
    const onRemoveFavorite = () => undefined;

    const props = emojiPickerFavoriteProps(intl, {
      favoriteEmojis,
      onAddFavorite,
      onRemoveFavorite,
    });

    expect(props.favoriteEmojis).toBe(favoriteEmojis);
    expect(props.onAddFavorite).toBe(onAddFavorite);
    expect(props.onRemoveFavorite).toBe(onRemoveFavorite);
  });

  it('resolves the favorite action labels', () => {
    const props = emojiPickerFavoriteProps(intl, {});

    expect(props.addToFavoritesLabel).toBe('emoji_button.add_to_favorites');
    expect(props.alreadyInFavoritesLabel).toBe(
      'emoji_button.already_in_favorites',
    );
    expect(props.removeFromFavoritesLabel).toBe(
      'emoji_button.remove_from_favorites',
    );
  });
});

describe('shouldIgnoreEmojiDropdownClose', () => {
  it('ignores clicks inside the emoji context menu', () => {
    const event = {
      target: { closest: (selector) => selector === '.emoji-context-menu' },
    };

    expect(shouldIgnoreEmojiDropdownClose(event)).toBe(true);
  });

  it('does not ignore clicks elsewhere', () => {
    const event = { target: { closest: () => null } };

    expect(shouldIgnoreEmojiDropdownClose(event)).toBe(false);
  });

  it('is safe for missing event or target', () => {
    expect(shouldIgnoreEmojiDropdownClose(undefined)).toBe(false);
    expect(shouldIgnoreEmojiDropdownClose({})).toBe(false);
  });
});
