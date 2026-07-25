import assert from 'node:assert/strict';
import test from 'node:test';

import { AuthenticationError } from '../errors.js';
import { createMisskeyCompat } from '../misskey_compat.js';
import { authorizeChannel as authorizeAdminChannel } from './admin.js';
import { authorizeChannel } from './antenna.js';
import { ACCESS_TOKEN_QUERY, authenticateFallback } from './auth.js';
import { createDomainFilter } from './domain_filter.js';
import { dispatchCallbacks } from './index.js';
import { acceptsLanguage } from './language.js';
import { createEnabledCheck } from './misskey.js';

test('Misskey fallback is fail-closed when compatibility is disabled', async () => {
  await assert.rejects(
    authenticateFallback({}, { i: 'token' }, () => assert.fail(), async () => false),
    AuthenticationError
  );
});

test('Misskey fallback is fail-closed when the setting lookup fails', async () => {
  await assert.rejects(
    authenticateFallback({}, { i: 'token' }, () => assert.fail(), async () => { throw new Error('database unavailable'); }),
    /database unavailable/
  );
});

test('OAuth token query loads community permissions only in roleplay mode', () => {
  assert.match(ACCESS_TOKEN_QUERY, /expires_in IS NULL/);
  assert.match(ACCESS_TOKEN_QUERY, /users\.disabled IS FALSE/);
  assert.match(ACCESS_TOKEN_QUERY, /accounts\.suspended_at IS NULL/);
  if (process.env.OC_ROLEPLAY_OPTION === 'true') {
    assert.match(ACCESS_TOKEN_QUERY, /extra_permissions/);
  } else {
    assert.doesNotMatch(ACCESS_TOKEN_QUERY, /extra_permissions/);
  }
});

test('Management timeline authorization requires roleplay mode and permission', () => {
  const previous = process.env.OC_ROLEPLAY_OPTION;

  try {
    delete process.env.OC_ROLEPLAY_OPTION;
    assert.throws(
      () => authorizeAdminChannel({ extraPermissions: 2 }, 'admin'),
      AuthenticationError
    );

    process.env.OC_ROLEPLAY_OPTION = 'true';
    assert.throws(
      () => authorizeAdminChannel({ extraPermissions: 0 }, 'admin'),
      AuthenticationError
    );
    assert.deepEqual(
      authorizeAdminChannel({ extraPermissions: 2 }, 'admin'),
      {
        channelIds: ['timeline:admin'],
        options: { needsFiltering: false, allowLocalOnly: true },
      }
    );
  } finally {
    if (previous === undefined) delete process.env.OC_ROLEPLAY_OPTION;
    else process.env.OC_ROLEPLAY_OPTION = previous;
  }
});

test('Antenna authorization rejects an antenna owned by another account', async () => {
  const pgPool = { query: async () => ({ rows: [] }) };

  await assert.rejects(
    authorizeChannel(pgPool, { accountId: '1' }, 'antenna', { antenna: '2' }),
    AuthenticationError
  );
});

test('Antenna authorization rejects lookup failures', async () => {
  const pgPool = { query: async () => { throw new Error('database unavailable'); } };

  await assert.rejects(
    authorizeChannel(pgPool, { accountId: '1' }, 'antenna', { antenna: '2' }),
    AuthenticationError
  );
});

test('Antenna authorization returns the owned stream contract', async () => {
  const pgPool = { query: async () => ({ rows: [{ id: '2', account_id: '1' }] }) };

  const result = await authorizeChannel(pgPool, { accountId: '1' }, 'antenna', { antenna: '2' });

  assert.deepEqual(result.channelIds, ['timeline:antenna:2']);
  assert.deepEqual(result.options.streamName, ['antenna', '2']);
});

test('missing status language is evaluated as und', () => {
  assert.equal(acceptsLanguage(['en'], undefined), false);
  assert.equal(acceptsLanguage(['und'], undefined), true);
});

test('domain filter checks status and boost authors with follow exceptions', async () => {
  const calls = [];
  const client = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      return { rows: [] };
    },
  };
  const filter = createDomainFilter(
    { accountId: '1' },
    {
      account: { id: '2', acct: 'alice@example.com' },
      reblog: { account: { id: '3', acct: 'bob@example.net' } },
    }
  );

  const result = await filter.query(client, true);

  assert.deepEqual(result.rows, []);
  assert.deepEqual(calls[0].params, ['1', ['example.com', 'example.net'], ['2', '3']]);
  assert.match(calls[0].sql, /NOT EXISTS \(SELECT 1 FROM follows/);
});

test('domain filter keeps a stable result when there are no remote domains', () => {
  const result = createDomainFilter({ accountId: '1', cachedFilters: {} }, { account: { id: '2', acct: 'alice' } });

  assert.equal(result, undefined);
});

test('Redis callback failures do not stop later callbacks', () => {
  const received = [];
  const errors = [];

  dispatchCallbacks([
    () => { throw new Error('bad callback'); },
    message => received.push(message),
  ], { event: 'update' }, error => errors.push(error));

  assert.equal(errors.length, 1);
  assert.deepEqual(received, [{ event: 'update' }]);
});

test('Misskey cleanup removes channel and note subscriptions', () => {
  const unsubscribed = [];
  const heartbeats = [];
  const compat = createMisskeyCompat({
    subscribe: () => {},
    unsubscribe: (channel) => unsubscribed.push(channel),
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => ({ channelIds: [] }),
    authorizeStatusAccess: async () => true,
    isEnabled: async () => true,
    logger: { error: () => {} },
  });
  const listener = () => {};
  const session = {
    misskey: { channels: new Map([['channel-id', { channelIds: ['misskey:timeline:1'], listener, stopHeartbeat: () => heartbeats.push('channel') }]]) },
    misskeyNotes: new Map([['note-id', { channel: 'misskey:note:1', listener, stopHeartbeat: () => heartbeats.push('note') }]]),
  };

  compat.cleanup(session);

  assert.deepEqual(unsubscribed, ['misskey:timeline:1', 'misskey:note:1']);
  assert.deepEqual(heartbeats, ['channel', 'note']);
  assert.equal(session.misskey.channels.size, 0);
  assert.equal(session.misskeyNotes.size, 0);
});

test('Misskey drive channel subscribes to the account stream and forwards typed events', async () => {
  const subscribed = [];
  let captured;
  const sent = [];
  const compat = createMisskeyCompat({
    subscribe: (channel, listener) => { subscribed.push(channel); captured = listener; },
    unsubscribe: () => {},
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => assert.fail('drive channel must not hit channelNameToIds'),
    authorizeStatusAccess: async () => true,
    isEnabled: async () => true,
    logger: { error: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['read:drive'] },
    websocket: { readyState: 1, OPEN: 1, send: (m) => sent.push(JSON.parse(m)) },
  };

  compat.handleMessage(session, { type: 'connect', body: { id: 'ch1', channel: 'drive' } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.deepEqual(subscribed, ['misskey:drive:7']);

  captured({ event: 'drive', payload: { type: 'fileCreated', body: { id: 'abc' } } });
  captured({ event: 'note', payload: { id: 'ignored' } });

  assert.deepEqual(sent, [{ type: 'channel', body: { id: 'ch1', type: 'fileCreated', body: { id: 'abc' } } }]);
});

test('Misskey drive channel rejects tokens without a drive-capable scope', async () => {
  let subscribedCount = 0;
  const compat = createMisskeyCompat({
    subscribe: () => { subscribedCount += 1; },
    unsubscribe: () => {},
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => ({ channelIds: [] }),
    authorizeStatusAccess: async () => true,
    isEnabled: async () => true,
    logger: { error: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['read:statuses'] },
    websocket: { readyState: 1, OPEN: 1, send: () => {} },
  };

  compat.handleMessage(session, { type: 'connect', body: { id: 'ch1', channel: 'drive' } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(subscribedCount, 0);
});

test('Misskey enabled lookup failures remain disabled', async () => {
  const errors = [];
  const enabled = createEnabledCheck(
    { query: async () => { throw new Error('database unavailable'); } },
    { error: (...args) => errors.push(args) },
    () => 20_000
  );

  assert.equal(await enabled(), false);
  assert.equal(errors.length, 1);
});
