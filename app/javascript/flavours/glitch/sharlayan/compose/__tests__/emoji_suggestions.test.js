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

    await fetchSuggestions(dispatch, getState, 'smile');

    expect(emojiSearch).toHaveBeenCalledWith('smile', 'en', 5);
    expect(dispatch).toHaveBeenCalledWith({
      token: 'smile',
      results: [
        { id: 'visible', custom: true },
        { id: 'native', custom: false },
      ],
    });
  });
});
