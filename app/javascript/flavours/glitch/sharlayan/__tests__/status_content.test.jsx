import { fromJS } from 'immutable';

let isSharlayanMfmStatus;
let renderSharlayanMfmContent;
let sharlayanStatusContentState;
let getSharlayanMfmSourceText;

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ getSharlayanMfmSourceText, isSharlayanMfmStatus, renderSharlayanMfmContent, sharlayanStatusContentState } =
    await import('../status_content'));
}, 30_000);

const metaState = (meta) => fromJS({ meta });

describe('Sharlayan status content helpers', () => {
  it('reads local MFM meta with safe defaults', () => {
    expect(sharlayanStatusContentState(metaState({}))).toEqual({
      localMfmEnabled: true,
      localMfmAnimations: true,
      localMfmFoldMode: 'sensitive',
    });

    expect(sharlayanStatusContentState(metaState({
      mfm_enabled: false,
      mfm_animations: false,
      mfm_fold_mode: 'all',
    }))).toEqual({
      localMfmEnabled: false,
      localMfmAnimations: false,
      localMfmFoldMode: 'all',
    });
  });

  it('gates MFM rendering on the status flag and both feature toggles', () => {
    const mfmStatus = fromJS({ mfm: true });
    const plainStatus = fromJS({ mfm: false });

    expect(isSharlayanMfmStatus(mfmStatus, { mfmEnabled: true, localMfmEnabled: true })).toBe(true);
    expect(isSharlayanMfmStatus(mfmStatus, { mfmEnabled: false, localMfmEnabled: true })).toBe(false);
    expect(isSharlayanMfmStatus(mfmStatus, { mfmEnabled: true, localMfmEnabled: false })).toBe(false);
    expect(isSharlayanMfmStatus(plainStatus, { mfmEnabled: true, localMfmEnabled: true })).toBeFalsy();
  });

  it('returns null for non-MFM statuses so the core EmojiHTML path is used', () => {
    const status = fromJS({ mfm: false, emojis: [] });
    const element = renderSharlayanMfmContent(status, {
      content: '<p>hi</p>',
      language: 'en',
      mfmEnabled: true,
      localMfmEnabled: true,
    });
    expect(element).toBeNull();
  });

  it('wraps MFM content and folds long text in a details element', () => {
    const status = fromJS({ mfm: true, mfm_text: 'x'.repeat(1001), emojis: [] });
    const element = renderSharlayanMfmContent(status, {
      content: '',
      language: 'en',
      mfmEnabled: true,
      localMfmEnabled: true,
      localMfmFoldMode: 'sensitive',
    });

    expect(element.props.className).toContain('status__content__text');
    expect(element.props.children.type).toBe('details');
  });

  it('does not fold short plain MFM text', () => {
    const status = fromJS({ mfm: true, mfm_text: 'hello', emojis: [] });
    const element = renderSharlayanMfmContent(status, {
      content: '',
      language: 'en',
      mfmEnabled: true,
      localMfmEnabled: true,
      localMfmFoldMode: 'sensitive',
    });

    expect(element.props.children.type).not.toBe('details');
  });

  it('uses translated content while a translation is active and restores the exact MFM source when it is removed', () => {
    const originalMfmText = '$[fg #123456 Original MFM source]';
    const content = '<p>Translated<br>content</p>';
    const status = fromJS({
      mfm: true,
      mfm_text: originalMfmText,
      translation: { contentHtml: content },
    });

    expect(getSharlayanMfmSourceText(status, content)).toBe('Translated\ncontent\n');
    expect(getSharlayanMfmSourceText(status.delete('translation'), content)).toBe(originalMfmText);

    const options = {
      content,
      language: 'en',
      mfmEnabled: true,
      localMfmEnabled: true,
    };
    expect(renderSharlayanMfmContent(status, options).props.children.props.text).toBe('Translated\ncontent\n');
    expect(renderSharlayanMfmContent(status.delete('translation'), options).props.children.props.text).toBe(originalMfmText);
  });

  it('extracts MFM text from the active content when no source is stored', () => {
    const status = fromJS({ mfm: true });

    expect(getSharlayanMfmSourceText(status, '<p>First<br>second</p>')).toBe('First\nsecond\n');
  });
});
