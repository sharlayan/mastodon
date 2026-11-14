import { fromJS } from 'immutable';

import { computeStatusActionBarOrder, selectStatusActionBarOrder, STATUS_ACTION_BAR_ITEMS } from '../items';

describe('computeStatusActionBarOrder', () => {
  it('uses the default order when no order is stored', () => {
    expect(computeStatusActionBarOrder()).toEqual(STATUS_ACTION_BAR_ITEMS);
  });

  it('keeps valid stored items and appends missing items', () => {
    expect(computeStatusActionBarOrder(['quote', 'clip'])).toEqual([
      'quote',
      'clip',
      'favourite',
      'reaction',
      'bookmark',
    ]);
  });

  it('removes unknown and duplicate items', () => {
    expect(computeStatusActionBarOrder(['clip', 'unknown', 'clip'])).toEqual([
      'clip',
      'favourite',
      'reaction',
      'bookmark',
      'quote',
    ]);
  });

  it('keeps the same normalized order while unrelated state changes', () => {
    const state = fromJS({
      compose: { text: '' },
      local_settings: { status_action_bar: { order: ['quote', 'clip'] } },
    });
    const changedCompose = state.setIn(['compose', 'text'], 'a');

    expect(selectStatusActionBarOrder(changedCompose)).toBe(selectStatusActionBarOrder(state));
  });
});
