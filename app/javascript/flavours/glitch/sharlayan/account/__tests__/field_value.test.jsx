import { isValidElement } from 'react';

let renderSharlayanFieldValue;

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ renderSharlayanFieldValue } = await import('../field_value'));
});

describe('renderSharlayanFieldValue', () => {
  const emojis = [];

  it('renders an MFM element when enabled and the value contains an MFM function', () => {
    const element = renderSharlayanFieldValue({
      valuePlain: '$[jelly hello]',
      emojis,
      mfmEnabled: true,
    });
    expect(isValidElement(element)).toBe(true);
  });

  it('returns null when MFM is disabled so the core FieldHTML path is used', () => {
    expect(
      renderSharlayanFieldValue({
        valuePlain: '$[jelly hello]',
        emojis,
        mfmEnabled: false,
      }),
    ).toBeNull();
  });

  it('returns null for plain values without MFM functions', () => {
    expect(
      renderSharlayanFieldValue({
        valuePlain: 'just plain text',
        emojis,
        mfmEnabled: true,
      }),
    ).toBeNull();
  });
});
