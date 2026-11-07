import assert from 'node:assert/strict';
import test from 'node:test';

import { createMisskeyCompat } from './misskey_compat.js';

const note = (overrides = {}) => ({
  id: 'note', userId: '0000000000000008', user: { host: null },
  text: 'text', cw: null, fileIds: [], replyId: null, renoteId: null,
  poll: null, localOnly: false, ...overrides,
});

const flush = () => new Promise((resolve) => setImmediate(resolve));

const fixture = (channelResult = { channelIds: ['timeline:public:local'], options: { filterLocal: false } }, isExcluded = () => false) => {
  const listeners = new Map();
  const sent = [];
  const filterCalls = [];
  const compat = createMisskeyCompat({
    subscribe: (channel, listener) => listeners.set(channel, listener),
    unsubscribe: (channel) => listeners.delete(channel),
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => channelResult,
    authorizeStatusAccess: async () => true,
    loadExcludedTimelineNote: async (viewerAccountId, targets) => {
      filterCalls.push({ viewerAccountId, targets });
      return isExcluded(targets);
    },
    loadGrantPermissions: async () => undefined,
    isEnabled: async () => true,
    logger: { error: () => {}, warn: () => {} },
  });
  const session = {
    request: { accountId: '7', scopes: ['read:statuses'] },
    websocket: { readyState: 1, OPEN: 1, send: (message) => sent.push(JSON.parse(message)) },
  };
  const connect = async (channel, params = {}) => {
    compat.handleMessage(session, { type: 'connect', body: { id: channel, channel, params } });
    await new Promise((resolve) => setImmediate(resolve));
  };
  const emit = (channel, payload) => listeners.get(`misskey:${channel}`)({ event: 'note', payload });

  return { compat, connect, emit, filterCalls, listeners, sent, session };
};

test('hybrid timeline merges home and local notes without duplicate delivery', async () => {
  const { compat, connect, emit, listeners, sent, session } = fixture();
  await connect('hybridTimeline');

  assert.deepEqual([...listeners.keys()], ['misskey:timeline:7', 'misskey:timeline:public:local']);

  emit('timeline:7', note({ id: 'remote', user: { host: 'remote.example' } }));
  emit('timeline:public:local', note({ id: 'local' }));
  emit('timeline:7', note({ id: 'local' }));
  emit('timeline:public:local', note({ id: 'unrelated-local-reply', replyId: 'parent', reply: { userId: '0000000000000009' } }));
  emit('timeline:7', note({ id: 'followed-reply', user: { host: 'remote.example' }, replyId: 'parent', reply: { userId: '0000000000000009' } }));
  await flush();

  assert.deepEqual(sent.map(({ body }) => body.body.id), ['remote', 'local', 'followed-reply']);

  compat.cleanup(session);
  assert.equal(listeners.size, 0);
});

test('hybrid timeline keeps the local feed gate before adding the home stream', async () => {
  const { connect, listeners, session } = fixture({ channelIds: [], options: { filterLocal: false } });
  await connect('hybridTimeline');
  assert.equal(listeners.size, 0);
  assert.equal(session.misskey.channels.size, 0);

  const restricted = fixture({ channelIds: ['timeline:public:local'], options: { filterLocal: true } });
  await restricted.connect('hybridTimeline');
  assert.equal(restricted.listeners.size, 0);
  assert.equal(restricted.session.misskey.channels.size, 0);
});

test('local timeline excludes unrelated replies by default and honors withReplies', async () => {
  const defaultTimeline = fixture();
  await defaultTimeline.connect('localTimeline');
  defaultTimeline.emit('timeline:public:local', note({ id: 'unrelated', replyId: 'parent', reply: { userId: '0000000000000009' } }));
  defaultTimeline.emit('timeline:public:local', note({ id: 'self-thread', replyId: 'parent', reply: { userId: '0000000000000008' } }));
  await flush();
  assert.deepEqual(defaultTimeline.sent.map(({ body }) => body.body.id), ['self-thread']);

  const withReplies = fixture();
  await withReplies.connect('localTimeline', { withReplies: true });
  withReplies.emit('timeline:public:local', note({ id: 'unrelated', replyId: 'parent', reply: { userId: '0000000000000009' } }));
  await flush();
  assert.deepEqual(withReplies.sent.map(({ body }) => body.body.id), ['unrelated']);
});

test('timeline file and renote filters use the serialized note and public feed settings', async () => {
  const home = fixture();
  await home.connect('homeTimeline', { withFiles: true, withRenotes: false });
  home.emit('timeline:7', note({ id: 'text-only' }));
  home.emit('timeline:7', note({ id: 'pure-renote', text: null, renoteId: 'target' }));
  home.emit('timeline:7', note({ id: 'quote-with-file', renoteId: 'target', fileIds: ['file'] }));
  assert.deepEqual(home.sent.map(({ body }) => body.body.id), ['quote-with-file']);

  const global = fixture({ channelIds: ['timeline:public'], options: { filterLocal: true, filterRemote: false } });
  await global.connect('globalTimeline');
  global.emit('timeline:public', note({ id: 'blocked-local' }));
  global.emit('timeline:public', note({ id: 'blocked-local-only', user: { host: 'remote.example' }, localOnly: true }));
  global.emit('timeline:public', note({ id: 'allowed-remote', user: { host: 'remote.example' } }));
  await flush();
  assert.deepEqual(global.sent.map(({ body }) => body.body.id), ['allowed-remote']);
});

test('timeline parameters leave antenna events unchanged', async () => {
  const antenna = fixture({ channelIds: ['timeline:antenna:12'] });
  await antenna.connect('antenna', { antennaId: '12', withFiles: true, withRenotes: false });
  antenna.emit('timeline:antenna:12', note({ id: 'pure-renote', text: null, renoteId: 'target' }));

  assert.deepEqual(antenna.sent.map(({ body }) => body.body.id), ['pure-renote']);
});

test('public timelines drop notes excluded by the viewer blocks, mutes and domain blocks', async () => {
  const local = fixture(undefined, (targets) => targets.accountIds.includes('9'));
  await local.connect('localTimeline');
  local.emit('timeline:public:local', note({ id: 'from-blocked', userId: '0000000000000009' }));
  local.emit('timeline:public:local', note({ id: 'mentions-muted', mentions: ['0000000000000009'] }));
  local.emit('timeline:public:local', note({ id: 'renote-of-blocked', text: null, renoteId: 'target', renote: { userId: '0000000000000009', user: { host: 'remote.example' } } }));
  local.emit('timeline:public:local', note({ id: 'allowed' }));
  await flush();

  assert.deepEqual(local.sent.map(({ body }) => body.body.id), ['allowed']);
  assert.deepEqual(local.filterCalls[2].targets, {
    authorIds: ['8', '9'],
    accountIds: ['8', '9'],
    domainTargets: [['remote.example', '9']],
  });
  assert.equal(local.filterCalls[0].viewerAccountId, '7');
});

test('hashtag channel applies feed access settings and viewer filtering', async () => {
  const hashtag = fixture({ channelIds: ['timeline:hashtag:test'], options: { filterLocal: false, filterRemote: true } }, (targets) => targets.accountIds.includes('9'));
  await hashtag.connect('hashtag', { q: [['test']] });
  hashtag.emit('timeline:hashtag:test', note({ id: 'remote', user: { host: 'remote.example' } }));
  hashtag.emit('timeline:hashtag:test', note({ id: 'blocked', userId: '0000000000000009' }));
  hashtag.emit('timeline:hashtag:test', note({ id: 'local' }));
  await flush();

  assert.deepEqual(hashtag.sent.map(({ body }) => body.body.id), ['local']);
});

test('home and antenna channels are not filtered again in streaming', async () => {
  const home = fixture({ channelIds: ['timeline:7'] }, () => true);
  await home.connect('homeTimeline');
  home.emit('timeline:7', note({ id: 'home' }));

  assert.deepEqual(home.sent.map(({ body }) => body.body.id), ['home']);
  assert.equal(home.filterCalls.length, 0);
});
