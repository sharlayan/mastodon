import { Map as ImmutableMap } from 'immutable';

import { importFetchedAccounts, importFetchedStatusReactions, importFetchedStatuses } from '../index';

const account = (id, moved = null) => ({
  id,
  username: `user${id}`,
  acct: `user${id}`,
  display_name: '',
  note: '',
  fields: [],
  emojis: [],
  moved,
});

const status = (id, author) => ({
  id,
  account: author,
  content: '',
  spoiler_text: '',
  sensitive: false,
  media_attachments: [],
  tagged_collections: [],
  emojis: [],
});

const getState = () => ImmutableMap({
  statuses: ImmutableMap(),
  local_settings: ImmutableMap(),
});

describe('status importer recursion guards', () => {
  it('imports each account only once when moved accounts form a cycle', () => {
    const first = account('1');
    const second = account('2');
    first.moved = second;
    second.moved = first;

    const action = importFetchedAccounts([first]);

    expect(action.payload.accounts.map(item => item.id)).toEqual(['1', '2']);
  });

  it('does not re-enter a status reached through a recursive quote', () => {
    const author = account('10');
    const quotedStatus = status('20', author);
    quotedStatus.quote = { quoted_status: quotedStatus };

    const dispatched = [];

    importFetchedStatuses([quotedStatus])(action => dispatched.push(action), getState);

    const statusesAction = dispatched.find(action => action.type === 'STATUSES_IMPORT');
    expect(statusesAction.statuses).toHaveLength(1);
  });

  it('stops a moved-account cycle reached through reaction users', () => {
    const author = account('10');
    const firstReactor = account('11');
    const secondReactor = account('12');
    firstReactor.moved = secondReactor;
    secondReactor.moved = firstReactor;

    const reactedStatus = {
      ...status('20', author),
      reactions: [{ name: '👍', users: [firstReactor] }],
    };
    const dispatched = [];

    importFetchedStatuses([reactedStatus])(action => dispatched.push(action), getState);

    const accountsAction = dispatched.find(action => action.type === 'accounts/importAccounts');
    expect(accountsAction.payload.accounts.map(item => item.id)).toEqual(['10', '11', '12']);
  });

  it('imports a reaction delta without touching the account store', () => {
    const reactionUpdate = {
      id: '20',
      reactions_count: 1,
      reactions: [{ name: '👍', count: 1, users: [{ id: '11', acct: 'user11', username: 'user11' }] }],
    };

    expect(importFetchedStatusReactions(reactionUpdate)).toEqual({ type: 'STATUS_REACTIONS_IMPORT', status: reactionUpdate });
  });
});
