import { fetchClip } from 'flavours/glitch/actions/clips';

import { clipsReducer } from '../clips';

describe('clipsReducer', () => {
  it('marks a clip that cannot be fetched as missing', () => {
    const state = clipsReducer(
      undefined,
      fetchClip.rejected(
        null,
        'request',
        { id: '7' },
        { error: new Error('404') },
      ),
    );

    expect(state.has('7')).toBe(true);
    expect(state.get('7')).toBeNull();
  });
});
