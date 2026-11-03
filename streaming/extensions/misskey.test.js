import assert from 'node:assert/strict';
import test from 'node:test';

import * as misskey from './misskey.js';

test('chat setting requires both chat and compatibility enabled and fails closed', async () => {
  assert.equal(await misskey.isChatEnabled({ query: async () => ({ rows: [{ var: 'chat_enabled', value: '--- true\n' }, { var: 'misskey_compat_enabled', value: '--- true\n' }] }) }), true);
  assert.equal(await misskey.isChatEnabled({ query: async () => ({ rows: [{ var: 'chat_enabled', value: '--- true\n' }] }) }), false);
  await assert.rejects(misskey.isChatEnabled({ query: async () => { throw new Error('unavailable'); } }), /unavailable/);
});

test('chat authorization validates IDs before querying and requires a membership result', async () => {
  let calls = 0;
  const pool = { query: async () => { calls += 1; return { rows: [] }; } };
  assert.equal(await misskey.authorizeChatAccess(pool, 'chatRoom', 'bad', { accountId: '7' }), false);
  assert.equal(calls, 0);
  assert.equal(await misskey.authorizeChatAccess(pool, 'chatRoom', '9', { accountId: '7' }), false);
  assert.equal(calls, 1);
  assert.equal(await misskey.authorizeChatAccess({ query: async () => ({ rows: [{ id: '9' }] }) }, 'chatRoom', '9', { accountId: '7' }), true);
});

test('chatUser can subscribe before the first direct conversation but cannot use self IDs', async () => {
  const pool = { query: async () => ({ rows: [{ id: '8' }] }) };
  assert.equal(await misskey.authorizeChatAccess(pool, 'chatUser', '8', { accountId: '7' }), true);
  assert.equal(await misskey.authorizeChatAccess(pool, 'chatUser', '7', { accountId: '7' }), false);
});

test('read updates bind viewer, subscription and message, rejecting malformed or missing messages', async () => {
  const calls = [];
  const pool = { query: async (sql, params) => { calls.push({ sql, params }); return { rows: [] }; } };
  assert.equal(await misskey.markChatRead(pool, 'chatRoom', '9', { accountId: '7' }, 'bad'), false);
  assert.equal(calls.length, 0);
  assert.equal(await misskey.markChatRead(pool, 'chatRoom', '9', { accountId: '7' }, '10'), false);
  assert.deepEqual(calls[0].params, ['7', '9', 'chatRoom', '10']);
  assert.match(calls[0].sql, /message\.chat_conversation_id = conversation\.id/);
  assert.match(calls[0].sql, /membership\.account_id = \$1/);
  assert.match(calls[0].sql, /last_read_message_id < message\.id/);
});

test('chat grant lookup fails closed instead of falling back to broad OAuth scopes', async () => {
  const grants = await misskey.loadGrantPermissions({ query: async () => { throw new Error('unavailable'); } }, { error: () => {} }, { accessTokenId: '1' }, true);
  assert.deepEqual(grants, []);
});
