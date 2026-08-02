import { describe, expect, it } from 'vitest';

import {
  DEFAULT_COLUMN_WIDTH,
  MAX_COLUMN_WIDTH,
  MIN_COLUMN_WIDTH,
  normalizeColumnWidth,
} from './column_width_context';

describe('normalizeColumnWidth', () => {
  it('uses the default for missing or invalid values', () => {
    expect(normalizeColumnWidth(undefined)).toBe(DEFAULT_COLUMN_WIDTH);
    expect(normalizeColumnWidth('invalid')).toBe(DEFAULT_COLUMN_WIDTH);
  });

  it('clamps values to the supported range', () => {
    expect(normalizeColumnWidth(MIN_COLUMN_WIDTH - 1)).toBe(MIN_COLUMN_WIDTH);
    expect(normalizeColumnWidth(MAX_COLUMN_WIDTH + 1)).toBe(MAX_COLUMN_WIDTH);
  });

  it('rounds valid numeric values to whole pixels', () => {
    expect(normalizeColumnWidth('512.6')).toBe(513);
  });
});
