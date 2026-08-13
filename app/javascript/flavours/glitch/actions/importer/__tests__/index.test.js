import { Map as ImmutableMap, fromJS } from 'immutable';

import { updateStatus } from '../../statuses';
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

  it('preserves reactions when importing a status edit', () => {
    const author = account('10');
    const editedStatus = {
      ...status('20', author),
      content: '<p>Edited</p>',
      reactions_count: 0,
      reactions: [],
      reacted: false,
    };
    const oldStatus = fromJS({
      id: '20',
      reactions_count: 1,
      reactions: [{ name: '👍', count: 1, me: true }],
      reacted: true,
    });
    const state = getState().setIn(['statuses', '20'], oldStatus);
    const dispatched = [];
    let importEdit;

    updateStatus(editedStatus, { bogusQuotePolicy: false })(action => { importEdit = action; });
    importEdit(action => dispatched.push(action), () => state);

    const statusesAction = dispatched.find(action => action.type === 'STATUSES_IMPORT');
    expect(statusesAction.statuses[0].content).toBe('<p>Edited</p>');
    expect(statusesAction.statuses[0].reactions_count).toBe(1);
    expect(statusesAction.statuses[0].reactions.toJS()).toEqual([{ name: '👍', count: 1, me: true }]);
    expect(statusesAction.statuses[0].reacted).toBe(true);
  });
});
