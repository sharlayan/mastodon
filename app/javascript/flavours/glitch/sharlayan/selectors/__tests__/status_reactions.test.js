import { fromJS, List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { applySharlayanStatusReactions, sharlayanStatusInputSelectors } from '../status_reactions';

const stateWith = (statuses, accounts) => fromJS({ statuses, accounts });

describe('Sharlayan status reaction selectors', () => {
  const [selectBase, selectReblog] = sharlayanStatusInputSelectors;

  it('resolves reaction users from account state for a status and its reblog', () => {
    const state = stateWith({
      '1': { reblog: '2', reactions: [{ name: '👍', users: [{ id: 'a' }] }] },
      '2': { reactions: [{ name: '🎉', users: [{ id: 'b' }, { id: 'missing' }] }] },
    }, {
      a: { id: 'a', username: 'alice' },
      b: { id: 'b', username: 'bob' },
    });

    const base = selectBase(state, { id: '1' });
    expect(base.get(0).map(acc => acc.get('username'))).toEqual(ImmutableList(['alice']));

    const reblog = selectReblog(state, { id: '1' });
    expect(reblog.get(0).map(acc => acc.get('id'))).toEqual(ImmutableList(['b', 'missing']));
  });

  it('returns null when there are no reactions or no reblog', () => {
    const state = stateWith({ '1': {} }, {});
    expect(selectBase(state, { id: '1' })).toBeNull();
    expect(selectReblog(state, { id: '1' })).toBeNull();
  });

  it('keeps resolved users stable while unrelated state changes', () => {
    const state = stateWith({
      '1': { reactions: [{ name: '👍', users: [{ id: 'a' }] }] },
    }, {
      a: { id: 'a', username: 'alice' },
    });
    const changedCompose = state.setIn(['compose', 'text'], 'a');

    expect(selectBase(changedCompose, { id: '1' })).toBe(selectBase(state, { id: '1' }));
  });

  it('keeps an embedded streaming reaction user when the account is not in state', () => {
    const state = stateWith({
      '1': { reactions: [{ name: '👍', users: [{ id: 'missing', username: 'alice' }] }] },
    }, {});

    expect(selectBase(state, { id: '1' }).getIn([0, 0, 'username'])).toBe('alice');
  });

  it('sets resolved reaction users onto the base status map', () => {
    const statusBase = fromJS({ reactions: [{ name: '👍', users: [{ id: 'a' }] }] });
    const resolved = ImmutableList([ImmutableList([ImmutableMap({ id: 'a', username: 'alice' })])]);

    const map = statusBase.asMutable();
    applySharlayanStatusReactions(map, statusBase, null, resolved, null);

    expect(map.getIn(['reactions', 0, 'users', 0, 'username'])).toEqual('alice');
  });

  it('sets resolved reaction users onto the reblog when present', () => {
    const statusBase = fromJS({});
    const statusReblog = fromJS({ reactions: [{ name: '🎉', users: [{ id: 'b' }] }] });
    const resolvedReblog = ImmutableList([ImmutableList([ImmutableMap({ id: 'b', username: 'bob' })])]);

    const map = statusBase.asMutable();
    applySharlayanStatusReactions(map, statusBase, statusReblog, null, resolvedReblog);

    expect(map.getIn(['reblog', 'reactions', 0, 'users', 0, 'username'])).toEqual('bob');
    expect(map.get('reactions')).toBeUndefined();
  });
});
