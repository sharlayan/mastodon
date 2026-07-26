let sharlayanAccountBioHtml;

const account = (overrides = {}) => ({
  note_emojified: '<p>emojified</p>',
  note_plain: 'hello world bio text',
  ...overrides,
});

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ sharlayanAccountBioHtml } = await import('../list_item'));
}, 30_000);

describe('sharlayanAccountBioHtml', () => {
  it('returns the emojified note when no character limit is set', () => {
    expect(sharlayanAccountBioHtml(account())).toBe('<p>emojified</p>');
  });

  it('truncates the plain note with an ellipsis past the limit', () => {
    expect(sharlayanAccountBioHtml(account(), 5)).toBe('hello…');
  });

  it('keeps the full plain note within the limit and escapes it', () => {
    expect(sharlayanAccountBioHtml(account({ note_plain: 'a<b>' }), 100)).toBe(
      'a&lt;b&gt;',
    );
  });

  it('handles a null plain note', () => {
    expect(sharlayanAccountBioHtml(account({ note_plain: null }), 100)).toBe('');
  });
});
