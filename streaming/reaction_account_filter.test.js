import assert from 'node:assert';
import { test } from 'node:test';

import { filterReactionAccounts, reactionAccountIds } from './reaction_account_filter.js';

const payload = {
  id: 'status-1',
  reactions: [
    {
      name: 'same',
      count: 3,
      account_ids: ['1', '2', '3'],
      users: [{ id: '1' }, { id: '2' }, { id: '3' }],
    },
    {
      name: 'hidden',
      count: 1,
      account_ids: ['2'],
      users: [{ id: '2' }],
    },
  ],
};

test('collects unique reaction account ids', () => {
  assert.deepEqual(reactionAccountIds(payload), ['1', '2', '3']);
});

test('removes excluded accounts from reaction counts and account lists', () => {
  const filtered = filterReactionAccounts(payload, ['2']);

  assert.equal(filtered.reactions.length, 1);
  assert.equal(filtered.reactions[0].count, 2);
  assert.deepEqual(filtered.reactions[0].account_ids, ['1', '3']);
  assert.deepEqual(filtered.reactions[0].users, [{ id: '1' }, { id: '3' }]);
  assert.equal(payload.reactions.length, 2);
});
