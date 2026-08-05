import { fromJS } from 'immutable';

import { describe, expect, it } from 'vitest';

import {
  COLLAPSE_BUTTON_CHARACTER_THRESHOLD,
  isLongStatus,
  isLengthyStatus,
  parseCharacterLimit,
  shouldShowCollapseButton,
} from './post_collapsing';

describe('post collapsing', () => {
  const characterLimit = 300;

  it('shows the collapse button for every post by default', () => {
    const status = fromJS({ contentHtml: '<p>Short text</p>' });

    expect(COLLAPSE_BUTTON_CHARACTER_THRESHOLD).toBe(0);
    expect(
      shouldShowCollapseButton(
        status,
        false,
        COLLAPSE_BUTTON_CHARACTER_THRESHOLD,
      ),
    ).toBe(true);
  });

  it('shows the collapse button from the configured number of visible characters', () => {
    const shortStatus = fromJS({
      contentHtml: `<p>${'가'.repeat(characterLimit - 1)}</p>`,
    });
    const longStatus = fromJS({
      contentHtml: `<p>${'가'.repeat(characterLimit)}</p>`,
    });

    expect(isLongStatus(shortStatus, characterLimit)).toBe(false);
    expect(isLongStatus(longStatus, characterLimit)).toBe(true);
  });

  it('does not count HTML markup toward the threshold', () => {
    const status = fromJS({
      contentHtml: `<p class="${'x'.repeat(400)}">Short text</p>`,
    });

    expect(isLongStatus(status, characterLimit)).toBe(false);
  });

  it('counts Unicode code points instead of UTF-16 code units', () => {
    const status = fromJS({
      contentHtml: `<p>${'😀'.repeat(characterLimit - 1)}</p>`,
    });

    expect(isLongStatus(status, characterLimit)).toBe(false);
  });

  it('supports a configurable limit and disables it with null', () => {
    const status = fromJS({ contentHtml: '<p>Short text</p>' });

    expect(shouldShowCollapseButton(status, false, 300)).toBe(false);
    expect(shouldShowCollapseButton(status, false, null)).toBe(true);
    expect(shouldShowCollapseButton(status, true, 300)).toBe(true);
  });

  it('uses rendered height when no automatic character limit is configured', () => {
    const status = fromJS({ contentHtml: '<p>Short text</p>' });

    expect(parseCharacterLimit('')).toBeNull();
    expect(parseCharacterLimit('0')).toBeNull();
    expect(parseCharacterLimit('1.5')).toBeNull();
    expect(isLengthyStatus(status, '', 401, 400)).toBe(true);
    expect(isLengthyStatus(status, '', 400, 400)).toBe(false);
  });

  it('uses character count instead of rendered height when configured', () => {
    const shortStatus = fromJS({
      contentHtml: `<p>${'가'.repeat(characterLimit - 1)}</p>`,
    });
    const longStatus = fromJS({
      contentHtml: `<p>${'가'.repeat(characterLimit)}</p>`,
    });

    expect(parseCharacterLimit(String(characterLimit))).toBe(characterLimit);
    expect(
      isLengthyStatus(shortStatus, String(characterLimit), 1000, 400),
    ).toBe(false);
    expect(isLengthyStatus(longStatus, String(characterLimit), 100, 400)).toBe(
      true,
    );
  });
});
