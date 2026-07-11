'use strict';

const MISSKEY_PREFIX = 'misskey:';

const MISSKEY_MESSAGE_TYPES = new Set([
  'connect',
  'disconnect',
  'channel',
  'ch',
  'subNote',
  's',
  'sr',
  'unsubNote',
  'un',
  'readNotification',
]);

const extractTag = (params) => {
  if (typeof params.tag === 'string') return params.tag;
  const q = params.q;
  if (Array.isArray(q) && Array.isArray(q[0]) && typeof q[0][0] === 'string') return q[0][0];
  return undefined;
};

/**
 * @param {string} channel
 * @param {Object} params
 * @param {Object} request
 * @param {Function} channelNameToIds
 * @returns {Promise<string[]>}
 */
const resolveChannel = (channel, params, request, channelNameToIds) => {
  switch (channel) {
  case 'homeTimeline':
    return Promise.resolve([`timeline:${request.accountId}`]);
  case 'localTimeline':
  case 'hybridTimeline':
    return channelNameToIds(request, 'public:local', {}).then((r) => r.channelIds);
  case 'globalTimeline':
    return channelNameToIds(request, 'public', {}).then((r) => r.channelIds);
  case 'userList':
    return channelNameToIds(request, 'list', { list: params.listId }).then((r) => r.channelIds);
  case 'antenna':
    return channelNameToIds(request, 'antenna', { antenna: params.antennaId }).then((r) => r.channelIds);
  case 'hashtag':
    return channelNameToIds(request, 'hashtag', { tag: extractTag(params) }).then((r) => r.channelIds);
  default:
    return Promise.reject(new Error(`Unsupported misskey channel: ${channel}`));
  }
};

/**
 * @param {Object} deps
 * @param {Function} deps.subscribe
 * @param {Function} deps.unsubscribe
 * @param {Function} deps.subscriptionHeartbeat
 * @param {Function} deps.channelNameToIds
 * @param {function(): Promise.<boolean>} deps.isEnabled
 * @param {import('pino').Logger} deps.logger
 */
const createMisskeyCompat = ({ subscribe, unsubscribe, subscriptionHeartbeat, channelNameToIds, isEnabled, logger }) => {
  const send = (ws, type, body) => {
    if (ws.readyState !== ws.OPEN) return;
    ws.send(JSON.stringify({ type, body }));
  };

  const store = (session) => {
    if (!session.misskey) session.misskey = { channels: new Map() };
    return session.misskey;
  };

  const noteStore = (session) => {
    if (!session.misskeyNotes) session.misskeyNotes = new Map();
    return session.misskeyNotes;
  };

  const subNote = (session, body) => {
    if (!body || (typeof body.id !== 'string' && typeof body.id !== 'number')) return;

    const noteId = String(body.id);
    const notes = noteStore(session);

    if (notes.has(noteId)) return;

    isEnabled().then((enabled) => {
      if (!enabled || notes.has(noteId)) return;

      const channel = `${MISSKEY_PREFIX}note:${noteId}`;

      const listener = (json) => {
        if (!json || json.event !== 'noteUpdated') return;
        send(session.websocket, 'noteUpdated', json.payload);
      };

      subscribe(channel, listener);
      const stopHeartbeat = subscriptionHeartbeat([channel]);

      notes.set(noteId, { channel, listener, stopHeartbeat });
    }).catch((err) => {
      logger.error({ err }, 'misskey compat note subscribe failed');
    });
  };

  const unsubNote = (session, body) => {
    if (!session.misskeyNotes || !body || (typeof body.id !== 'string' && typeof body.id !== 'number')) return;

    const noteId = String(body.id);
    const sub = session.misskeyNotes.get(noteId);
    if (!sub) return;

    unsubscribe(sub.channel, sub.listener);
    sub.stopHeartbeat();
    session.misskeyNotes.delete(noteId);
  };

  const connect = (session, body) => {
    if (!body || typeof body.id !== 'string' || typeof body.channel !== 'string') return;

    const { channel, id } = body;
    const params = body.params || {};
    const channels = store(session).channels;

    if (channels.has(id)) return;

    isEnabled().then((enabled) => {
      if (!enabled || channels.has(id)) return undefined;

      return resolveChannel(channel, params, session.request, channelNameToIds);
    }).then((channelIds) => {
      if (!channelIds || channels.has(id)) return;

      const misskeyChannelIds = channelIds.map((c) => MISSKEY_PREFIX + c);

      const listener = (json) => {
        if (!json || json.event !== 'note') return;
        send(session.websocket, 'channel', { id, type: 'note', body: json.payload });
      };

      misskeyChannelIds.forEach((c) => subscribe(c, listener));
      const stopHeartbeat = subscriptionHeartbeat(misskeyChannelIds);

      channels.set(id, { channelIds: misskeyChannelIds, listener, stopHeartbeat });
    }).catch((err) => {
      logger.error({ err }, 'misskey compat channel connect failed');
    });
  };

  const teardown = (channels, id) => {
    const sub = channels.get(id);
    if (!sub) return;
    sub.channelIds.forEach((c) => unsubscribe(c, sub.listener));
    sub.stopHeartbeat();
    channels.delete(id);
  };

  const disconnect = (session, body) => {
    if (!session.misskey || !body || typeof body.id !== 'string') return;
    teardown(session.misskey.channels, body.id);
  };

  const cleanup = (session) => {
    if (session.misskey) {
      for (const id of Array.from(session.misskey.channels.keys())) {
        teardown(session.misskey.channels, id);
      }
    }

    if (session.misskeyNotes) {
      for (const noteId of Array.from(session.misskeyNotes.keys())) {
        unsubNote(session, { id: noteId });
      }
    }
  };

  const handleMessage = (session, json) => {
    switch (json.type) {
    case 'connect':
      connect(session, json.body);
      break;
    case 'disconnect':
      disconnect(session, json.body);
      break;
    case 's':
    case 'sr':
    case 'subNote':
      subNote(session, json.body);
      break;
    case 'un':
    case 'unsubNote':
      unsubNote(session, json.body);
      break;
    default:
      break;
    }
  };

  const isMisskeyType = (type) => MISSKEY_MESSAGE_TYPES.has(type);

  return { handleMessage, cleanup, isMisskeyType };
};

export { createMisskeyCompat };
