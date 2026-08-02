import assert from 'node:assert';
import { test } from 'node:test';

import { excludedReactionAccountIds, filterReactionAccounts, filterReactionPayload, reactionAccountIds } from './reaction_account_filter.js';

const payload = {
  id: 'status-1',
  reactions_count: 4,
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
  assert.equal(filtered.reactions_count, 2);
  assert.equal(payload.reactions_count, 4);
  assert.equal(payload.reactions.length, 2);
});

test('queries mute and both block directions for reaction accounts', async () => {
  const calls = [];
  const pgPool = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      return { rows: [{ id: 2 }] };
    },
  };

  assert.deepEqual(await excludedReactionAccountIds(pgPool, '9', ['1', '2']), ['2']);
  assert.deepEqual(calls[0].params, ['9', ['1', '2']]);
  assert.match(calls[0].sql, /FROM mutes/);
  assert.equal((calls[0].sql.match(/FROM blocks/g) || []).length, 2);
});

test('keeps reactions from accounts without mute or block relationships', async () => {
  const pgPool = { query: async () => ({ rows: [] }) };

  const filtered = await filterReactionPayload(pgPool, '9', payload);

  assert.deepEqual(filtered, payload);
  assert.equal(filtered.reactions_count, 4);
});

test('calculates slugcat reaction counts independently for viewers with different mutes', async () => {
  const slugcatPayload = {
    id: 'status-2',
    reactions_count: 2,
    reactions: [{
      name: 'slugcat',
      count: 2,
      account_ids: ['30', '40'],
      users: [{ id: '30', username: 'carol' }, { id: '40', username: 'dave' }],
    }],
  };
  const pgPool = {
    query: async (_sql, [viewerAccountId]) => ({
      rows: viewerAccountId === '10' ? [{ id: '30' }] : [],
    }),
  };

  const viewerA = await filterReactionPayload(pgPool, '10', slugcatPayload);
  const viewerB = await filterReactionPayload(pgPool, '20', slugcatPayload);

  assert.equal(viewerA.reactions[0].count, 1);
  assert.deepEqual(viewerA.reactions[0].account_ids, ['40']);
  assert.deepEqual(viewerA.reactions[0].users, [{ id: '40', username: 'dave' }]);
  assert.equal(viewerA.reactions_count, 1);

  assert.equal(viewerB.reactions[0].count, 2);
  assert.deepEqual(viewerB.reactions[0].account_ids, ['30', '40']);
  assert.equal(viewerB.reactions_count, 2);

  assert.equal(slugcatPayload.reactions[0].count, 2);
  assert.equal(slugcatPayload.reactions_count, 2);
});
