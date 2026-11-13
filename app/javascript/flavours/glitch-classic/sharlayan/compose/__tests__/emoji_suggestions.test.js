import { createFetchComposeEmojiSuggestions } from '../emoji_suggestions';

describe('compose emoji suggestions', () => {
  it('keeps the search contract and removes only picker-muted custom emoji', async () => {
    const emojiSearch = vi.fn().mockResolvedValue([
      { id: 'muted', custom: true },
      { id: 'visible', custom: true },
      { id: 'native', custom: false },
    ]);
    const readySuggestions = vi.fn((token, results) => ({ token, results }));
    const dispatch = vi.fn();
    const getState = () => ({
      custom_emoji_mutes: {
        items: [
          { prefix: 'muted', domain: null, hide_in_picker: true },
          { prefix: 'visible', domain: null, hide_in_picker: false },
        ],
      },
    });
    const fetchSuggestions = createFetchComposeEmojiSuggestions({ emojiSearch, readySuggestions });

    const signal = new AbortController().signal;

    await fetchSuggestions(dispatch, getState, 'smile', signal);

    expect(emojiSearch).toHaveBeenCalledWith({ token: 'smile', locale: 'en', limit: 5, signal });
    expect(dispatch).toHaveBeenCalledWith({
      token: 'smile',
      results: [
        { id: 'visible', custom: true },
        { id: 'native', custom: false },
      ],
    });
  });

  it('dispatches nothing when the search was aborted', async () => {
    const emojiSearch = vi.fn().mockResolvedValue(null);
    const readySuggestions = vi.fn();
    const dispatch = vi.fn();
    const getState = vi.fn();
    const fetchSuggestions = createFetchComposeEmojiSuggestions({ emojiSearch, readySuggestions });

    await fetchSuggestions(dispatch, getState, 'smile', new AbortController().signal);

    expect(getState).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });
});
