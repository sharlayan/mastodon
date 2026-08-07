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
      reactions: [{ name: '👍', count: 2, users: [] }],
    }));

    expect(nextState.getIn(['20', 'content'])).toBe('<p>Keep this content</p>');
    expect(nextState.getIn(['20', 'reactions_count'])).toBe(2);
    expect(nextState.getIn(['20', 'reactions', 0, 'count'])).toBe(2);
    expect(nextState.getIn(['20', 'reactions', 0, 'me'])).toBe(true);
  });

  it('derives display_name_html for reaction users from the lightweight payload', () => {
    const state = fromJS({
      20: { id: '20', reactions_count: 0, reactions: [] },
    });

    const nextState = statuses(state, importStatusReactions({
      id: '20',
      reactions_count: 2,
      reactions: [{
        name: '👍',
        count: 2,
        users: [
          {
            id: '11',
            username: 'alice',
            acct: 'alice',
            display_name: '<b>Alice</b>',
            avatar: 'alice.gif',
            avatar_static: 'alice.png',
            emojis: [
              {
                shortcode: 'wave',
                url: 'wave.gif',
                static_url: 'wave.png',
              },
            ],
          },
          {
            id: '12',
            username: 'bob',
            acct: 'bob@remote.test',
            display_name: '  ',
            avatar: 'bob.gif',
            avatar_static: 'bob.png',
            emojis: [],
          },
        ],
      }],
    }));

    const users = nextState.getIn(['20', 'reactions', 0, 'users']);

    expect(users.getIn([0, 'display_name_html'])).toBe('&lt;b&gt;Alice&lt;/b&gt;');
    expect(users.getIn([1, 'display_name_html'])).toBe('bob');
    expect(users.get(0).display_name_html).toBe('&lt;b&gt;Alice&lt;/b&gt;');
    expect(users.get(0).avatar_decorations).toEqual([]);
    expect(users.get(0).emojis.get(0).shortcode).toBe('wave');
  });

  it('leaves a reaction without users untouched', () => {
    const state = fromJS({
      20: { id: '20', reactions_count: 0, reactions: [] },
    });

    const nextState = statuses(state, importStatusReactions({
      id: '20',
      reactions_count: 1,
      reactions: [{ name: '👍', count: 1 }],
    }));

    expect(nextState.getIn(['20', 'reactions', 0, 'users'])).toBeUndefined();
  });
});
