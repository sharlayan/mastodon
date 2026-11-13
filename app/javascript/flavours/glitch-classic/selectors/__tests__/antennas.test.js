import { fromJS } from 'immutable';

import { getAvailableAntennas } from '../antennas';

describe('antenna selectors', () => {
  it('keeps the available list stable while unrelated state changes', () => {
    const state = fromJS({
      antennas: {
        first: { id: 'first', title: 'First' },
        missing: null,
      },
      compose: { text: '' },
    });
    const changedCompose = state.setIn(['compose', 'text'], 'a');

    expect(getAvailableAntennas(changedCompose)).toBe(
      getAvailableAntennas(state),
    );
    expect(getAvailableAntennas(state).map((item) => item.get('id')).toArray()).toEqual(['first']);
  });
});
