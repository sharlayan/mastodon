'use strict';

import { filterPayload as filterCustomEmojiPayload, mutedNoteUpdate } from './custom_emoji_filter.js';

const MISSKEY_PREFIX = 'misskey:';
const MAX_CHANNEL_SUBSCRIPTIONS = 50;
const MAX_NOTE_SUBSCRIPTIONS = 100;
const MAX_CHANNEL_ID_LENGTH = 128;
const MAX_CHANNEL_NAME_LENGTH = 64;
const MAX_DATABASE_ID = 9223372036854775807n;
const REACTION_NOTE_UPDATE_TYPES = new Set(['reacted', 'unreacted']);

const MI_ID_TIME2000 = 946684800000;

/* eslint-disable jsdoc/reject-function-type -- Dependency signatures are defined by the streaming server. */
/**
 * Decode a Misskey-compat aidx id back to the underlying Mastodon id.
 * Mirrors MisskeyCompat::MiId#decode.
 * @param {string|number|undefined|null} mid
 * @returns {string|undefined}
 */
const decodeMiId = (mid) => {
  if (mid === undefined || mid === null) return undefined;
  const str = String(mid);
  if (!/^[0-9a-z]{16}$/.test(str)) return str;
  if (str.startsWith('0')) {
    return String(parseInt(str, 36));
  }
  const ms = BigInt(parseInt(str.slice(0, 8), 36) + MI_ID_TIME2000);
  const seq = BigInt(parseInt(str.slice(8, 16), 36));
  return ((ms << 16n) | seq).toString();
};

const decodeDatabaseId = (value) => {
  const decoded = decodeMiId(value);
  if (!decoded || !/^\d{1,19}$/.test(decoded)) return undefined;

  const id = BigInt(decoded);
  return id <= MAX_DATABASE_ID ? decoded : undefined;
};

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

const hasScope = (request, ...scopes) => Array.isArray(request.scopes) && scopes.some((scope) => request.scopes.includes(scope));

const canReadStatuses = (request, grantPermissions) => (Array.isArray(grantPermissions) ? grantPermissions.includes('read:account') : hasScope(request, 'read', 'read:statuses'));

const canReadDrive = (request, grantPermissions) => (Array.isArray(grantPermissions) ? grantPermissions.includes('read:drive') : hasScope(request, 'read', 'read:drive'));

const isSelfChannel = (channel) => channel === 'drive';

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
    return channelNameToIds(request, 'list', { list: decodeMiId(params.listId) }).then((r) => r.channelIds);
  case 'antenna':
    return channelNameToIds(request, 'antenna', { antenna: decodeMiId(params.antennaId) }).then((r) => r.channelIds);
  case 'hashtag':
    return channelNameToIds(request, 'hashtag', { tag: extractTag(params) }).then((r) => r.channelIds);
  case 'drive':
    return Promise.resolve([`drive:${request.accountId}`]);
  default:
    return Promise.reject(new Error(`Unsupported misskey channel: ${channel}`));
  }
};
/* eslint-enable jsdoc/reject-function-type */

/* eslint-disable jsdoc/reject-function-type -- Dependency signatures are defined by the streaming server. */
/**
 * @param {Object} deps
 * @param {Function} deps.subscribe
 * @param {Function} deps.unsubscribe
 * @param {function(string[]): function(): void} deps.subscriptionHeartbeat
 * @param {Function} deps.channelNameToIds
 * @param {Function} deps.authorizeStatusAccess
 * @param {Function} deps.loadExcludedReactionAccountIds
 * @param {Function} deps.loadGrantPermissions
 * @param {function(): Promise.<boolean>} deps.isEnabled
 * @param {import('pino').Logger} deps.logger
 */
const createMisskeyCompat = ({ subscribe, unsubscribe, subscriptionHeartbeat, channelNameToIds, authorizeStatusAccess, loadExcludedReactionAccountIds, loadGrantPermissions, isEnabled, logger }) => {
  const send = (session, type, body) => {
    const ws = session.websocket;
    if (ws.readyState !== ws.OPEN) return;
    if (mutedNoteUpdate(type, body, session.request.customEmojiMutes)) return;
    body = structuredClone(body);
    filterCustomEmojiPayload(body, session.request.customEmojiMutes);
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

  const grantPermissions = (session) => {
    if (!session.misskeyGrant) session.misskeyGrant = loadGrantPermissions(session.request);
    return session.misskeyGrant;
  };

  const authorize = (session, channel) => grantPermissions(session).then((permissions) => {
    const authorized = channel === 'drive' ? canReadDrive(session.request, permissions) : canReadStatuses(session.request, permissions);

    if (!authorized) {
      logger.warn({ accountId: session.request.accountId, channel }, 'misskey compat subscription rejected: insufficient token permissions');
    }

    return authorized;
  });

  const subNote = (session, body) => {
    if (!body || (typeof body.id !== 'string' && typeof body.id !== 'number')) return;

    const noteId = String(body.id);
    const statusId = decodeDatabaseId(noteId);
    const notes = noteStore(session);

    if (!statusId || notes.has(noteId) || notes.size >= MAX_NOTE_SUBSCRIPTIONS) return;

    const reservation = {};
    notes.set(noteId, reservation);
    isEnabled().then((enabled) => {
      if (!enabled || notes.get(noteId) !== reservation) return false;

      return authorize(session, 'note');
    }).then((permitted) => {
      if (!permitted || notes.get(noteId) !== reservation) return false;

      return authorizeStatusAccess(statusId, session.request);
    }).then((authorized) => {
      if (!authorized || notes.get(noteId) !== reservation) return;

      const channel = `${MISSKEY_PREFIX}note:${noteId}`;

      const listener = (json) => {
        if (!json || json.event !== 'noteUpdated') return;

        const reactionAccountId = REACTION_NOTE_UPDATE_TYPES.has(json.payload?.type) ? decodeDatabaseId(json.payload?.body?.userId) : undefined;
        if (!reactionAccountId) {
          send(session, 'noteUpdated', json.payload);
          return;
        }

        loadExcludedReactionAccountIds(session.request.accountId, [reactionAccountId])
          .then((excludedAccountIds) => {
            if (excludedAccountIds.length === 0) send(session, 'noteUpdated', json.payload);
          })
          .catch((err) => logger.error({ err }, 'misskey compat reaction filter failed'));
      };

      subscribe(channel, listener);
      const stopHeartbeat = subscriptionHeartbeat([channel]);

      notes.set(noteId, { channel, listener, stopHeartbeat });
    }).catch((err) => {
      logger.error({ err }, 'misskey compat note subscribe failed');
    }).finally(() => {
      if (notes.get(noteId) === reservation) notes.delete(noteId);
    });
  };

  const unsubNote = (session, body) => {
    if (!session.misskeyNotes || !body || (typeof body.id !== 'string' && typeof body.id !== 'number')) return;

    const noteId = String(body.id);
    const sub = session.misskeyNotes.get(noteId);
    if (!sub) return;

    if (!sub.channel) {
      session.misskeyNotes.delete(noteId);
      return;
    }

    unsubscribe(sub.channel, sub.listener);
    sub.stopHeartbeat();
    session.misskeyNotes.delete(noteId);
  };

  const connect = (session, body) => {
    if (!body || typeof body.id !== 'string' || typeof body.channel !== 'string') return;

    const { channel, id } = body;
    if (id.length > MAX_CHANNEL_ID_LENGTH || channel.length > MAX_CHANNEL_NAME_LENGTH) return;

    const params = body.params || {};
    const channels = store(session).channels;

    if (channels.has(id) || channels.size >= MAX_CHANNEL_SUBSCRIPTIONS) return;

    const reservation = {};
    channels.set(id, reservation);
    isEnabled().then((enabled) => {
      if (!enabled || channels.get(id) !== reservation) return false;

      return authorize(session, channel);
    }).then((authorized) => {
      if (!authorized || channels.get(id) !== reservation) return undefined;

      return resolveChannel(channel, params, session.request, channelNameToIds);
    }).then((channelIds) => {
      if (!channelIds || channels.get(id) !== reservation) return;

      const misskeyChannelIds = channelIds.map((c) => MISSKEY_PREFIX + c);

      const listener = isSelfChannel(channel)
        ? (json) => {
          if (!json || json.event !== 'drive') return;
          send(session, 'channel', { id, type: json.payload.type, body: json.payload.body });
        }
        : (json) => {
          if (!json || json.event !== 'note') return;
          send(session, 'channel', { id, type: 'note', body: json.payload });
        };

      misskeyChannelIds.forEach((c) => subscribe(c, listener));
      const stopHeartbeat = subscriptionHeartbeat(misskeyChannelIds);

      channels.set(id, { channelIds: misskeyChannelIds, listener, stopHeartbeat });
    }).catch((err) => {
      logger.error({ err }, 'misskey compat channel connect failed');
    }).finally(() => {
      if (channels.get(id) === reservation) channels.delete(id);
    });
  };

  const teardown = (channels, id) => {
    const sub = channels.get(id);
    if (!sub) return;
    if (!sub.channelIds) {
      channels.delete(id);
      return;
    }

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
/* eslint-enable jsdoc/reject-function-type */

export { createMisskeyCompat };
