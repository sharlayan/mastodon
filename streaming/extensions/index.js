import { authenticateFallback, standardTokenFromRequest } from './auth.js';
import * as antenna from './antenna.js';
import { createDomainFilter } from './domain_filter.js';
import { acceptsLanguage } from './language.js';
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

  return {
    authenticateFallback: (req, query, accountFromToken) => authenticateFallback(req, query, accountFromToken, misskey.isEnabled),
    standardTokenFromRequest,
    channel: {
      fromPath: (req) => antenna.channelNameFromPath(req.path),
      authorize: (req, name, params) => antenna.authorizeChannel(deps.pgPool, req, name, params),
      streamName: antenna.streamName,
    },
    filterPayload(req, payload) {
      return {
        acceptedLanguage: acceptsLanguage(req.chosenLanguages, payload.language),
        domain: createDomainFilter(req, payload),
      };
    },
    attachSession(session, parseJSON) {
      session.websocket.on('close', () => misskey.cleanup(session));
      session.websocket.on('message', (data, isBinary) => {
        if (isBinary) return;
        const json = parseJSON(data.toString('utf8'), session.request);
        if (json && misskey.isMisskeyType(json.type)) misskey.handleMessage(session, json);
      });
    },
    dispatchCallbacks,
  };
};

export { CHANNEL_NAMES, createStreamingExtensions, dispatchCallbacks };
