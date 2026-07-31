import { describe, expect, it } from 'vitest';

import { createBlock } from './blocks';

describe('createBlock', () => {
  it('prevents new image blocks from being enlarged by default', () => {
    expect(createBlock('image')).toMatchObject({
      type: 'image',
      noUpscale: true,
    });
  });
});
