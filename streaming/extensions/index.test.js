import assert from 'node:assert/strict';
import test from 'node:test';

import { AuthenticationError } from '../errors.js';
import { createMisskeyCompat } from '../misskey_compat.js';
import { authorizeChannel } from './antenna.js';
import { ACCESS_TOKEN_QUERY, authenticateFallback } from './auth.js';
import { createDomainFilter } from './domain_filter.js';
import { dispatchCallbacks } from './index.js';
import { acceptsLanguage } from './language.js';
import { createEnabledCheck, loadGrantPermissions } from './misskey.js';

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

test('OAuth token query preserves expiry and account security conditions', () => {
  assert.match(ACCESS_TOKEN_QUERY, /expires_in IS NULL/);
  assert.match(ACCESS_TOKEN_QUERY, /users\.disabled IS FALSE/);
  assert.match(ACCESS_TOKEN_QUERY, /accounts\.suspended_at IS NULL/);
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
    loadGrantPermissions: async () => undefined,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
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

test('Misskey note subscription limit reserves slots before asynchronous authorization', async () => {
  let authorizationCalls = 0;
  let releaseAuthorization;
  const pendingAuthorization = new Promise((resolve) => { releaseAuthorization = resolve; });
  const compat = createMisskeyCompat({
    subscribe: () => assert.fail('pending subscriptions must not reach Redis'),
    unsubscribe: () => {},
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => ({ channelIds: [] }),
    authorizeStatusAccess: async () => {
      authorizationCalls += 1;
      return pendingAuthorization;
    },
    loadGrantPermissions: async () => undefined,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['read:statuses'] },
    websocket: { readyState: 1, OPEN: 1, send: () => {} },
  };

  for (let id = 1; id <= 101; id += 1) {
    compat.handleMessage(session, { type: 'subNote', body: { id: String(id) } });
  }
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(authorizationCalls, 100);
  assert.equal(session.misskeyNotes.size, 100);

  releaseAuthorization(false);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(session.misskeyNotes.size, 0);
});

test('Misskey channel subscription limit reserves slots before asynchronous resolution', async () => {
  let resolutionCalls = 0;
  let releaseResolution;
  const pendingResolution = new Promise((resolve) => { releaseResolution = resolve; });
  const compat = createMisskeyCompat({
    subscribe: () => assert.fail('pending subscriptions must not reach Redis'),
    unsubscribe: () => {},
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => {
      resolutionCalls += 1;
      return pendingResolution;
    },
    authorizeStatusAccess: async () => true,
    loadGrantPermissions: async () => undefined,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['read:statuses'] },
    websocket: { readyState: 1, OPEN: 1, send: () => {} },
  };

  for (let id = 1; id <= 51; id += 1) {
    compat.handleMessage(session, { type: 'connect', body: { id: `channel-${id}`, channel: 'localTimeline' } });
  }
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(resolutionCalls, 50);
  assert.equal(session.misskey.channels.size, 50);

  releaseResolution(undefined);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(session.misskey.channels.size, 0);
});

test('Misskey note subscriptions reject values outside the database ID range', async () => {
  let authorizationCalls = 0;
  const compat = createMisskeyCompat({
    subscribe: () => assert.fail('invalid IDs must not reach Redis'),
    unsubscribe: () => {},
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => ({ channelIds: [] }),
    authorizeStatusAccess: async () => { authorizationCalls += 1; return true; },
    loadGrantPermissions: async () => undefined,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['read:statuses'] },
    websocket: { readyState: 1, OPEN: 1, send: () => {} },
  };

  compat.handleMessage(session, { type: 'subNote', body: { id: '9223372036854775808' } });
  compat.handleMessage(session, { type: 'subNote', body: { id: '1'.repeat(1_000) } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(authorizationCalls, 0);
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
    loadGrantPermissions: async () => undefined,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
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
    loadGrantPermissions: async () => undefined,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['read:statuses'] },
    websocket: { readyState: 1, OPEN: 1, send: () => {} },
  };

  compat.handleMessage(session, { type: 'connect', body: { id: 'ch1', channel: 'drive' } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(subscribedCount, 0);
});

test('MiAuth grant lookup keys on the access token and stays undefined when unavailable', async () => {
  const calls = [];
  const errors = [];
  const pgPool = {
    query: async (sql, params) => {
      calls.push({ sql, params });
      return { rows: [{ permissions: ['read:drive'] }] };
    },
  };

  assert.deepEqual(await loadGrantPermissions(pgPool, { error: () => {} }, { accessTokenId: '5' }), ['read:drive']);
  assert.deepEqual(calls[0].params, ['5']);
  assert.match(calls[0].sql, /FROM misskey_access_grants WHERE access_token_id = \$1/);

  assert.equal(await loadGrantPermissions({ query: async () => ({ rows: [] }) }, { error: () => {} }, { accessTokenId: '5' }), undefined);
  assert.equal(await loadGrantPermissions({ query: async () => { throw new Error('relation does not exist'); } }, { error: (...args) => errors.push(args) }, { accessTokenId: '5' }), undefined);
  assert.equal(errors.length, 1);
});

const createCompatFixture = (grantPermissions) => {
  const subscribed = [];
  const compat = createMisskeyCompat({
    subscribe: (channel) => subscribed.push(channel),
    unsubscribe: () => {},
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => ({ channelIds: ['timeline:public:local'] }),
    authorizeStatusAccess: async () => true,
    loadGrantPermissions: async () => grantPermissions,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['misskey'], accessTokenId: '5' },
    websocket: { readyState: 1, OPEN: 1, send: () => {} },
  };

  return { compat, session, subscribed };
};

test('MiAuth tokens can stream timelines and notes without a Mastodon read scope', async () => {
  const { compat, session, subscribed } = createCompatFixture(['read:account']);

  compat.handleMessage(session, { type: 'connect', body: { id: 'ch1', channel: 'homeTimeline' } });
  compat.handleMessage(session, { type: 'connect', body: { id: 'ch2', channel: 'localTimeline' } });
  compat.handleMessage(session, { type: 'subNote', body: { id: '9abcdefghijklmno' } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.deepEqual(subscribed, ['misskey:timeline:7', 'misskey:timeline:public:local', 'misskey:note:9abcdefghijklmno']);
});

test('MiAuth tokens need read:account for timelines and notes', async () => {
  for (const permissions of [[], ['read:drive']]) {
    const { compat, session, subscribed } = createCompatFixture(permissions);

    compat.handleMessage(session, { type: 'connect', body: { id: 'ch1', channel: 'homeTimeline' } });
    compat.handleMessage(session, { type: 'connect', body: { id: 'ch2', channel: 'localTimeline' } });
    compat.handleMessage(session, { type: 'subNote', body: { id: '9abcdefghijklmno' } });
    await new Promise((resolve) => setImmediate(resolve));

    assert.deepEqual(subscribed, []);
  }
});

test('MiAuth tokens need the read:drive permission for the drive channel', async () => {
  const withoutDrive = createCompatFixture([]);
  const withDrive = createCompatFixture(['read:drive']);

  withoutDrive.compat.handleMessage(withoutDrive.session, { type: 'connect', body: { id: 'ch1', channel: 'drive' } });
  withDrive.compat.handleMessage(withDrive.session, { type: 'connect', body: { id: 'ch1', channel: 'drive' } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.deepEqual(withoutDrive.subscribed, []);
  assert.deepEqual(withDrive.subscribed, ['misskey:drive:7']);
});

test('The MiAuth grant is looked up once per session', async () => {
  let lookups = 0;
  const compat = createMisskeyCompat({
    subscribe: () => {},
    unsubscribe: () => {},
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => ({ channelIds: ['timeline:public:local'] }),
    authorizeStatusAccess: async () => true,
    loadGrantPermissions: async () => { lookups += 1; return []; },
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['misskey'], accessTokenId: '5' },
    websocket: { readyState: 1, OPEN: 1, send: () => {} },
  };

  compat.handleMessage(session, { type: 'connect', body: { id: 'ch1', channel: 'homeTimeline' } });
  compat.handleMessage(session, { type: 'connect', body: { id: 'ch2', channel: 'localTimeline' } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(lookups, 1);
});

test('Tokens with neither a read scope nor a MiAuth grant are rejected', async () => {
  const warnings = [];
  const session = {
    request: { accountId: '7', scopes: ['misskey'] },
    websocket: { readyState: 1, OPEN: 1, send: () => {} },
  };

  const compat = createMisskeyCompat({
    subscribe: () => assert.fail('must not subscribe'),
    unsubscribe: () => {},
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => ({ channelIds: [] }),
    authorizeStatusAccess: async () => true,
    loadGrantPermissions: async () => undefined,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: (...args) => warnings.push(args) },
  });

  compat.handleMessage(session, { type: 'connect', body: { id: 'ch1', channel: 'homeTimeline' } });
  compat.handleMessage(session, { type: 'subNote', body: { id: '9abcdefghijklmno' } });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(warnings.length, 2);
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
