import { authenticateFallback, standardTokenFromRequest } from './auth.js';
import * as antenna from './antenna.js';
import { createDomainFilter } from './domain_filter.js';
import { createMisskeyExtension } from './misskey.js';

const CHANNEL_NAMES = [antenna.CHANNEL_NAME];

const dispatchCallbacks = (callbacks, message, onError) => {
  callbacks.forEach(callback => {
    try {
      callback(message);
    } catch (err) {
      onError(err);
    }
  });
};

const createStreamingExtensions = (deps) => {
  const misskey = createMisskeyExtension(deps);
  deps.wss.on('connection', (websocket, request, logger) => {
    const session = { websocket, request, logger, subscriptions: {} };
    websocket.on('close', () => misskey.cleanup(session));
    websocket.on('message', (data, isBinary) => {
      if (isBinary) return;
      const json = deps.parseJSON(data.toString('utf8'), request);
      if (json && misskey.isMisskeyType(json.type)) misskey.handleMessage(session, json);
    });
  });

  return {
    authenticateFallback: (req, query, accountFromToken) => authenticateFallback(req, query, accountFromToken, misskey.isEnabled),
    standardTokenFromRequest,
    channel: {
      fromPath: (req) => antenna.channelNameFromPath(req.path),
      authorize: (req, name, params) => antenna.authorizeChannel(deps.pgPool, req, name, params),
    },
    preparePayload(req, payload) {
      if (!payload.language) payload.language = 'und';
      return createDomainFilter(req, payload);
    },
    dispatchCallbacks,
  };
};

export { CHANNEL_NAMES, createStreamingExtensions, dispatchCallbacks };
