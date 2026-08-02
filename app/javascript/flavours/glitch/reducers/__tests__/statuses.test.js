import { fromJS } from 'immutable';

import { importStatusReactions } from '../../actions/importer';
import statuses from '../statuses';

describe('statuses reducer reaction updates', () => {
  it('updates only reaction fields and preserves the current account reaction', () => {
    const state = fromJS({
      20: {
        id: '20',
        content: '<p>Keep this content</p>',
        reactions_count: 1,
        reactions: [{ name: '👍', count: 1, me: true, users: [] }],
      },
    });

    const nextState = statuses(state, importStatusReactions({
      id: '20',
      reactions_count: 2,
      reactions: [{ name: '👍', count: 2, users: [{ id: '11' }] }],
    }));

    expect(nextState.getIn(['20', 'content'])).toBe('<p>Keep this content</p>');
    expect(nextState.getIn(['20', 'reactions_count'])).toBe(2);
    expect(nextState.getIn(['20', 'reactions', 0, 'count'])).toBe(2);
    expect(nextState.getIn(['20', 'reactions', 0, 'me'])).toBe(true);
  });
});
