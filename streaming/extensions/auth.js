import { AuthenticationError } from '../errors.js';
import { firstParam } from '../utils.js';

const ACCESS_TOKEN_QUERY = "SELECT oauth_access_tokens.id, oauth_access_tokens.resource_owner_id, users.account_id, users.chosen_languages, oauth_access_tokens.scopes, COALESCE(user_roles.permissions, 0) AS permissions FROM oauth_access_tokens INNER JOIN users ON oauth_access_tokens.resource_owner_id = users.id INNER JOIN accounts ON accounts.id = users.account_id LEFT OUTER JOIN user_roles ON user_roles.id = users.role_id WHERE oauth_access_tokens.token = $1 AND oauth_access_tokens.revoked_at IS NULL AND (oauth_access_tokens.expires_in IS NULL OR oauth_access_tokens.created_at + oauth_access_tokens.expires_in * INTERVAL '1 second' > NOW()) AND users.disabled IS FALSE AND accounts.suspended_at IS NULL LIMIT 1";

const standardTokenFromRequest = (req, query) => {
  const authorization = req.headers.authorization;
  const accessToken = query?.access_token;
  const protocolToken = req.headers['sec-websocket-protocol'];
  const standardToken = accessToken ? firstParam(accessToken) : protocolToken ? firstParam(protocolToken) : undefined;

  return authorization ? authorization.replace(/^Bearer /, '') : standardToken;
};

const authenticateFallback = async (req, query, accountFromToken, isMisskeyEnabled) => {
  const token = query?.i ? firstParam(query.i) : undefined;
  if (!token) throw new AuthenticationError('Missing access token');
  if (!await isMisskeyEnabled()) throw new AuthenticationError('Misskey compatibility is disabled');

  return accountFromToken(token, req);
};

export { ACCESS_TOKEN_QUERY, authenticateFallback, standardTokenFromRequest };
