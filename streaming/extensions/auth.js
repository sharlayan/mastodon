import { AuthenticationError } from '../errors.js';
import { firstParam } from '../utils.js';
import { isAdminTimelineEnabled } from './admin_gate.js';

const PERMISSION_ADMINISTRATOR = 1 << 0;
const EXTRA_PERMISSIONS_ALL = (1 << 3) - 1;

const adminTimelineAccessSelect = isAdminTimelineEnabled()
  ? `, CASE
      WHEN COALESCE(user_roles.permissions, 0) & ${PERMISSION_ADMINISTRATOR} = ${PERMISSION_ADMINISTRATOR}
        THEN ${EXTRA_PERMISSIONS_ALL}
      ELSE COALESCE(user_roles.extra_permissions, 0)
        | COALESCE((SELECT extra_permissions FROM user_roles WHERE id = -99), 0)
        | CASE
            WHEN (COALESCE(user_roles.extra_permissions, 0) | COALESCE((SELECT extra_permissions FROM user_roles WHERE id = -99), 0)) & 2 = 2
              THEN 4
            ELSE 0
          END
    END AS extra_permissions,
    CASE
      WHEN user_roles.id <> -99 AND user_roles.position = (SELECT MAX(position) FROM user_roles WHERE id <> -99)
        THEN TRUE
      ELSE FALSE
    END AS admin_timeline_owner_viewer`
  : '';
const ACCESS_TOKEN_QUERY = `SELECT oauth_access_tokens.id, oauth_access_tokens.resource_owner_id, users.account_id, users.chosen_languages, oauth_access_tokens.scopes, COALESCE(user_roles.permissions, 0) AS permissions, COALESCE(oauth_applications.superapp, FALSE) AS superapp${adminTimelineAccessSelect} FROM oauth_access_tokens INNER JOIN users ON oauth_access_tokens.resource_owner_id = users.id INNER JOIN accounts ON accounts.id = users.account_id LEFT OUTER JOIN user_roles ON user_roles.id = users.role_id LEFT OUTER JOIN oauth_applications ON oauth_applications.id = oauth_access_tokens.application_id WHERE oauth_access_tokens.token = $1 AND oauth_access_tokens.revoked_at IS NULL AND (oauth_access_tokens.expires_in IS NULL OR oauth_access_tokens.created_at + oauth_access_tokens.expires_in * INTERVAL '1 second' > CURRENT_TIMESTAMP AT TIME ZONE 'UTC') AND users.disabled IS FALSE AND accounts.suspended_at IS NULL LIMIT 1`;

const authenticateFallback = async (req, query, accountFromToken, isMisskeyEnabled) => {
  const token = query?.i ? firstParam(query.i) : undefined;
  if (!token) throw new AuthenticationError('Missing access token');
  if (!await isMisskeyEnabled()) throw new AuthenticationError('Misskey compatibility is disabled');

  return accountFromToken(token, req);
};

export { ACCESS_TOKEN_QUERY, authenticateFallback };
