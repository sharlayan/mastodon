import { afterEach, describe, expect, it } from 'vitest';

import { isRedesignEnabled } from './environment';

describe('redesign feature gates', () => {
  afterEach(() => {
    window.localStorage.removeItem('experiments');
  });

  it('keeps the redesign disabled when experiments are requested', () => {
    window.localStorage.setItem('experiments', 'redesign');

    expect(isRedesignEnabled()).toBe(false);
  });
});
