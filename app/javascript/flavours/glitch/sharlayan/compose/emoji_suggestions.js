import { isCustomEmojiMuted } from 'flavours/glitch/utils/custom_emoji_mutes';

export const filterComposeEmojiSuggestions = (results, pickerMutes) =>
  results.filter((result) => !(result.custom && isCustomEmojiMuted(result.id, undefined, pickerMutes)));

export const createFetchComposeEmojiSuggestions = ({ emojiSearch, readySuggestions }) => async (dispatch, getState, token, signal) => {
  const results = await emojiSearch({
    token,
    // Right now we are hard-coding the locale to English since the picker search only supports English.
    // Once we replace the legacy picker we can remove this and use the actual locale of the user.
    locale: 'en',
    limit: 5,
    signal,
  });

  if (!results) {
    return;
  }

  const pickerMutes = getState().custom_emoji_mutes.items.filter((mute) => mute.hide_in_picker);
  dispatch(readySuggestions(token, filterComposeEmojiSuggestions(results, pickerMutes)));
};
