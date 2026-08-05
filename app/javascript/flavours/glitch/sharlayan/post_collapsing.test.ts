import { fromJS } from 'immutable';

import { describe, expect, it } from 'vitest';

import {
  COLLAPSE_BUTTON_CHARACTER_THRESHOLD,
  isLongStatus,
  shouldShowCollapseButton,
} from './post_collapsing';

describe('post collapsing', () => {
  it('shows the collapse button from 300 visible characters', () => {
    const shortStatus = fromJS({
      contentHtml: `<p>${'가'.repeat(COLLAPSE_BUTTON_CHARACTER_THRESHOLD - 1)}</p>`,
    });
    const longStatus = fromJS({
      contentHtml: `<p>${'가'.repeat(COLLAPSE_BUTTON_CHARACTER_THRESHOLD)}</p>`,
    });

    expect(isLongStatus(shortStatus, COLLAPSE_BUTTON_CHARACTER_THRESHOLD)).toBe(
      false,
    );
    expect(isLongStatus(longStatus, COLLAPSE_BUTTON_CHARACTER_THRESHOLD)).toBe(
      true,
    );
  });

  it('does not count HTML markup toward the threshold', () => {
    const status = fromJS({
      contentHtml: `<p class="${'x'.repeat(400)}">Short text</p>`,
    });

    expect(isLongStatus(status, COLLAPSE_BUTTON_CHARACTER_THRESHOLD)).toBe(
      false,
    );
  });

  it('counts Unicode code points instead of UTF-16 code units', () => {
    const status = fromJS({
      contentHtml: `<p>${'😀'.repeat(COLLAPSE_BUTTON_CHARACTER_THRESHOLD - 1)}</p>`,
    });

    expect(isLongStatus(status, COLLAPSE_BUTTON_CHARACTER_THRESHOLD)).toBe(
      false,
    );
  });

  it('supports a configurable limit and disables it with null', () => {
    const status = fromJS({ contentHtml: '<p>Short text</p>' });

    expect(shouldShowCollapseButton(status, false, 300)).toBe(false);
    expect(shouldShowCollapseButton(status, false, null)).toBe(true);
    expect(shouldShowCollapseButton(status, true, 300)).toBe(true);
  });
});
