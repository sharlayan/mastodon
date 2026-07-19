import { isCustomEmojiMuted } from 'flavours/glitch/utils/custom_emoji_mutes';

export const filterComposeEmojiSuggestions = (results, pickerMutes) =>
  results.filter((result) => !(result.custom && isCustomEmojiMuted(result.id, undefined, pickerMutes)));

export const createFetchComposeEmojiSuggestions = ({ emojiSearch, readySuggestions }) => async (dispatch, getState, token) => {
  const results = await emojiSearch(token, 'en', 5);
  const pickerMutes = getState().custom_emoji_mutes.items.filter((mute) => mute.hide_in_picker);
  dispatch(readySuggestions(token, filterComposeEmojiSuggestions(results, pickerMutes)));
};
