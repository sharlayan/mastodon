import assert from 'node:assert/strict';
import test from 'node:test';

import { createMisskeyCompat } from './misskey_compat.js';

const note = (overrides = {}) => ({
  id: 'note', userId: '0000000000000008', user: { host: null },
  text: 'text', cw: null, fileIds: [], replyId: null, renoteId: null,
  poll: null, localOnly: false, ...overrides,
});

const fixture = (channelResult = { channelIds: ['timeline:public:local'], options: { filterLocal: false } }) => {
  const listeners = new Map();
  const sent = [];
  const compat = createMisskeyCompat({
    subscribe: (channel, listener) => listeners.set(channel, listener),
    unsubscribe: (channel) => listeners.delete(channel),
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => channelResult,
    authorizeStatusAccess: async () => true,
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

  return { compat, connect, emit, listeners, sent, session };
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
  assert.deepEqual(defaultTimeline.sent.map(({ body }) => body.body.id), ['self-thread']);

  const withReplies = fixture();
  await withReplies.connect('localTimeline', { withReplies: true });
  withReplies.emit('timeline:public:local', note({ id: 'unrelated', replyId: 'parent', reply: { userId: '0000000000000009' } }));
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
  assert.deepEqual(global.sent.map(({ body }) => body.body.id), ['allowed-remote']);
});

test('timeline parameters leave antenna events unchanged', async () => {
  const antenna = fixture({ channelIds: ['timeline:antenna:12'] });
  await antenna.connect('antenna', { antennaId: '12', withFiles: true, withRenotes: false });
  antenna.emit('timeline:antenna:12', note({ id: 'pure-renote', text: null, renoteId: 'target' }));

  assert.deepEqual(antenna.sent.map(({ body }) => body.body.id), ['pure-renote']);
});

const chatFixture = () => {
  const listeners = new Map();
  const sent = [];
  const reads = [];
  const state = { enabled: true, allowed: true, grants: undefined };
  const compat = createMisskeyCompat({
    subscribe: (channel, listener) => {
      if (!listeners.has(channel)) listeners.set(channel, new Set());
      listeners.get(channel).add(listener);
    },
    unsubscribe: (channel, listener) => listeners.get(channel)?.delete(listener),
    subscriptionHeartbeat: () => () => {},
    channelNameToIds: async () => ({ channelIds: [] }),
    loadGrantPermissions: async () => state.grants,
    loadChatGrantPermissions: async () => state.grants,
    isEnabled: async () => true,
    isChatEnabled: async () => state.enabled,
    authorizeChatAccess: async (_channel, _targetId, _request, event) => state.allowed && (!event || state.eventAllowed !== false),
    markChatRead: async (channel, targetId, request, messageId) => { reads.push({ channel, targetId, viewer: request.accountId, messageId }); return true; },
    logger: { error: () => {}, warn: () => {} },
  });
  const session = { request: { accountId: '7', scopes: ['read'] }, websocket: { readyState: 1, OPEN: 1, send: (value) => sent.push(JSON.parse(value)) } };
  const flush = () => new Promise((resolve) => setImmediate(resolve));
  const connect = async (channel, params = {}, id = channel) => {
    compat.handleMessage(session, { type: 'connect', body: { id, channel, params } });
    await flush();
  };
  const emit = async (channel, payload) => {
    for (const listener of listeners.get(channel) ?? []) listener({ event: 'chat', payload });
    await flush();
  };
  return { compat, session, state, sent, reads, connect, emit, flush, listeners };
};

test('chatUser and chatRoom deliver viewer-specific message and mutation envelopes', async () => {
  const chat = chatFixture();
  await chat.connect('chatUser', { otherId: '0000000000000008' });
  await chat.connect('chatRoom', { roomId: '0000000000000009' });
  for (const type of ['message', 'updated', 'deleted', 'react', 'unreact', 'roomUpdated']) {
    await chat.emit('misskey:chatRoom:7:9', { type, conversationId: '9', messageId: '10', body: type === 'deleted' ? '000000000000000a' : { text: type } });
  }
  await chat.emit('misskey:chatUser:7:8', { type: 'message', conversationId: '10', body: { text: 'first direct message' } });

  assert.deepEqual(chat.sent.map(({ body }) => [body.id, body.type]), [
    ...['message', 'updated', 'deleted', 'react', 'unreact', 'roomUpdated'].map((type) => ['chatRoom', type]), ['chatUser', 'message'],
  ]);
  assert.equal(chat.sent.at(-1).body.body.text, 'first direct message');
});

test('chat rejects invalid targets, unrelated permissions and disabled feature', async () => {
  const chat = chatFixture();
  for (const params of [null, 'room', [], 9]) {
    assert.doesNotThrow(() => chat.compat.handleMessage(chat.session, { type: 'connect', body: { id: 'invalid', channel: 'chatRoom', params } }));
  }
  for (const roomId of ['', 'bad-id', '9223372036854775808', '0', {}]) await chat.connect('chatRoom', { roomId });
  await chat.connect('chatUser', { otherId: '7' });
  chat.state.grants = ['read:account'];
  await chat.connect('main');
  await chat.connect('chatRoom', { roomId: '9' });
  chat.state.grants = ['read:chat'];
  chat.state.enabled = false;
  await chat.connect('chatRoom', { roomId: '9' });
  assert.equal(chat.session.misskey.channels.size, 0);
});

test('chat main notifications require chat permission and current conversation access', async () => {
  const chat = chatFixture();
  chat.state.grants = ['read:chat'];
  await chat.connect('main');
  await chat.emit('misskey:chatMain:7', { type: 'newChatMessage', conversationId: '9', body: { text: 'private' } });
  chat.state.allowed = false;
  await chat.emit('misskey:chatMain:7', { type: 'newChatMessage', conversationId: '9', body: { text: 'removed' } });
  chat.state.allowed = true;
  await chat.emit('misskey:chatMain:7', { type: 'newChatMessage', conversationId: '10', body: { text: 'other conversation' } });
  assert.deepEqual(chat.sent.map(({ body }) => body.body.text), ['private', 'other conversation']);
});

test('chat requires broad OAuth read and does not accept read:statuses alone', async () => {
  const chat = chatFixture();
  chat.session.request.scopes = ['read:statuses'];
  await chat.connect('chatUser', { otherId: '8' });
  await chat.connect('chatRoom', { roomId: '9' });
  await chat.connect('main');
  assert.equal(chat.session.misskey.channels.size, 0);
});

test('chat rechecks feature and grant permissions after subscribing', async () => {
  const chat = chatFixture();
  chat.state.grants = ['read:chat'];
  await chat.connect('chatRoom', { roomId: '9' });
  chat.state.grants = ['read:account'];
  await chat.emit('misskey:chatRoom:7:9', { type: 'message', conversationId: '9', body: { text: 'revoked' } });
  chat.state.grants = ['read:chat'];
  chat.state.enabled = false;
  await chat.emit('misskey:chatRoom:7:9', { type: 'message', conversationId: '9', body: { text: 'disabled' } });
  assert.deepEqual(chat.sent, []);
});

test('an inaccessible group message does not end the subscription while membership remains', async () => {
  const chat = chatFixture();
  await chat.connect('chatRoom', { roomId: '9' });
  chat.state.eventAllowed = false;
  await chat.emit('misskey:chatRoom:7:9', { type: 'message', conversationId: '9', body: { text: 'already deleted' } });
  chat.state.eventAllowed = true;
  await chat.emit('misskey:chatRoom:7:9', { type: 'message', conversationId: '9', body: { text: 'next message' } });
  assert.deepEqual(chat.sent.map(({ body }) => body.body.text), ['next message']);

  chat.state.allowed = false;
  await chat.emit('misskey:chatRoom:7:9', { type: 'message', conversationId: '9', body: { text: 'after removal' } });
  assert.equal(chat.session.misskey.channels.size, 0);
  assert.deepEqual(chat.sent.map(({ body }) => body.body.text), ['next message']);
});

test('room deletion closes a previously authorized subscription without requiring its deleted row', async () => {
  const chat = chatFixture();
  await chat.connect('chatRoom', { roomId: '9' });
  chat.state.allowed = false;
  await chat.emit('misskey:chatRoom:7:9', { type: 'roomDeleted', conversationId: '9', body: null });
  await chat.emit('misskey:chatRoom:7:9', { type: 'message', conversationId: '9', body: { text: 'late' } });
  assert.deepEqual(chat.sent, [{ type: 'channel', body: { id: 'chatRoom', type: 'roomDeleted', body: null } }]);
  assert.equal(chat.session.misskey.channels.size, 0);
});

test('deleted events permit only the matching message ID, never a content payload', async () => {
  const chat = chatFixture();
  await chat.connect('chatRoom', { roomId: '9' });
  for (const body of [{ text: 'hidden' }, '11', null]) {
    await chat.emit('misskey:chatRoom:7:9', { type: 'deleted', conversationId: '9', messageId: '10', body });
  }
  await chat.emit('misskey:chatRoom:7:9', { type: 'deleted', conversationId: '9', messageId: '10', body: '000000000000000a' });

  assert.deepEqual(chat.sent, [{ type: 'channel', body: { id: 'chatRoom', type: 'deleted', body: '000000000000000a' } }]);
});

test('channel read commands use the authorized subscription target and decoded message ID', async () => {
  const chat = chatFixture();
  await chat.connect('chatRoom', { roomId: '9' });
  chat.compat.handleMessage(chat.session, { type: 'channel', body: { id: 'chatRoom', type: 'read', body: { id: '000000000000000a', roomId: '999' } } });
  await chat.flush();
  chat.compat.handleMessage(chat.session, { type: 'ch', body: { id: 'unknown', type: 'read', body: { id: '10' } } });
  chat.state.grants = [];
  chat.compat.handleMessage(chat.session, { type: 'ch', body: { id: 'chatRoom', type: 'read', body: { id: '11' } } });
  await chat.flush();
  assert.deepEqual(chat.reads, [{ channel: 'chatRoom', targetId: '9', viewer: '7', messageId: '10' }]);
});
