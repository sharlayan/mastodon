import { createLruCache } from './lru_cache';
import { shouldFoldMfm } from './mfm_cache';

vi.mock('./mfm_renderer', () => ({
  hasAnyMfmFn: (text: string) => text.includes('$['),
  hasSensitiveFoldTags: (text: string) => text.includes('$[spin'),
}));

describe('mfm cache helpers', () => {
  it('evicts the least recently used entry beyond the limit', () => {
    const cache = createLruCache<number>(2);
    const compute = vi.fn((value: number) => value);

    cache('a', () => compute(1));
    cache('b', () => compute(2));
    cache('a', () => compute(3));
    cache('c', () => compute(4));

    expect(cache('a', () => compute(5))).toBe(1);
    expect(cache('b', () => compute(6))).toBe(6);
  });

  it('folds by mode and length like the inline checks it replaces', () => {
    expect(shouldFoldMfm('$[spin hi]', 'all')).toBe(true);
    expect(shouldFoldMfm('plain', 'all')).toBe(false);
    expect(shouldFoldMfm('$[x2 hi]', 'sensitive')).toBe(false);
    expect(shouldFoldMfm('$[spin hi]', 'sensitive')).toBe(true);
    expect(shouldFoldMfm('$[spin hi]', 'off')).toBe(false);
    expect(shouldFoldMfm('x'.repeat(1001), 'off')).toBe(true);
  });
});
