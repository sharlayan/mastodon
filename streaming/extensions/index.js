import * as admin from './admin.js';
import * as antenna from './antenna.js';
import { authenticateFallback } from './auth.js';
import { createDomainFilter } from './domain_filter.js';
import { normalizeLanguage } from './language.js';
import { createMisskeyExtension } from './misskey.js';

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
    channel: {
      fromPath: (req) => antenna.channelNameFromPath(req.path) ?? admin.channelNameFromPath(req.path),
      authorize: async (req, name, params) =>
        (await antenna.authorizeChannel(deps.pgPool, req, name, params)) ??
        admin.authorizeChannel(req, name),
    },
    preparePayload(req, payload) {
      payload.language = normalizeLanguage(payload.language);
      return createDomainFilter(req, payload);
    },
    dispatchCallbacks,
  };
};

export { createStreamingExtensions, dispatchCallbacks };
