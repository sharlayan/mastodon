import { emojiPickerFavoriteMessages } from './messages';

export function emojiPickerFavoritesCategoryLabel(intl) {
  return intl.formatMessage(emojiPickerFavoriteMessages.favorites);
}

export function emojiPickerFavoriteProps(
  intl,
  { favoriteEmojis, onAddFavorite, onRemoveFavorite },
) {
  return {
    favoriteEmojis,
    onAddFavorite,
    onRemoveFavorite,
    addToFavoritesLabel: intl.formatMessage(
      emojiPickerFavoriteMessages.add_to_favorites,
    ),
    alreadyInFavoritesLabel: intl.formatMessage(
      emojiPickerFavoriteMessages.already_in_favorites,
    ),
    removeFromFavoritesLabel: intl.formatMessage(
      emojiPickerFavoriteMessages.remove_from_favorites,
    ),
  };
}

export function shouldIgnoreEmojiDropdownClose(e) {
  return Boolean(e?.target?.closest?.('.emoji-context-menu'));
}
