import { createMisskeyCompat } from '../misskey_compat.js';
import { excludedReactionAccountIds } from '../reaction_account_filter.js';

import { createDomainTargetsFilter } from './domain_filter.js';

const createEnabledCheck = (pgPool, logger, now = Date.now) => {
  let setting = { value: false, checkedAt: 0 };
  let refresh;

  return async () => {
    const checkedAt = now();
    if (checkedAt - setting.checkedAt < 15000) return setting.value;
    if (refresh) return refresh;

    refresh = Promise.resolve()
      .then(() => pgPool.query("SELECT value FROM settings WHERE var = 'misskey_compat_enabled' LIMIT 1"))
      .then((result) => {
        const enabled = result.rows.length > 0 && result.rows[0].value === "--- true\n";
        setting = { value: enabled, checkedAt: now() };
        return enabled;
      })
      .catch((err) => {
        logger.error({ err }, 'Failed to read misskey_compat_enabled setting');
        setting = { value: false, checkedAt: now() };
        return false;
      })
      .finally(() => {
        refresh = undefined;
      });

    return refresh;
  };
};

const authorizeStatusAccess = async (pgPool, statusId, req) => {
  if (!statusId || !/^\d+$/.test(statusId)) return false;

  const result = await pgPool.query(`
    SELECT 1
    FROM statuses
    WHERE statuses.id = $1
      AND (
        statuses.account_id = $2
        OR statuses.visibility IN (0, 1)
        OR statuses.visibility = 2 AND EXISTS (
          SELECT 1 FROM follows
          WHERE follows.account_id = $2
            AND follows.target_account_id = statuses.account_id
        )
        OR statuses.visibility IN (3, 4) AND EXISTS (
          SELECT 1 FROM mentions
          WHERE mentions.status_id = statuses.id
            AND mentions.account_id = $2
            AND mentions.silent = FALSE
        )
      )
    LIMIT 1
  `, [statusId, req.accountId]);

  return result.rows.length > 0;
};

const excludedTimelineNote = async (pgPool, viewerAccountId, { authorIds, accountIds, domainTargets }) => {
  if (!viewerAccountId || accountIds.length === 0) return false;

  const queries = [
    pgPool.query(`
      SELECT 1
      FROM blocks
      WHERE (account_id = $1 AND target_account_id = ANY($2::bigint[]))
         OR (target_account_id = $1 AND account_id = ANY($3::bigint[]))
      UNION
      SELECT 1
      FROM mutes
      WHERE account_id = $1
        AND target_account_id = ANY($2::bigint[])
      LIMIT 1
    `, [viewerAccountId, accountIds, authorIds]),
  ];

  const domainFilter = createDomainTargetsFilter({ accountId: viewerAccountId }, domainTargets);
  if (domainFilter) queries.push(domainFilter.query(pgPool));

  const results = await Promise.all(queries);
  return results.some((result) => result.rows.length > 0);
};

const loadGrantPermissions = async (pgPool, logger, req) => {
  if (!req.accessTokenId) return undefined;

  try {
    const result = await pgPool.query('SELECT permissions FROM misskey_access_grants WHERE access_token_id = $1 LIMIT 1', [req.accessTokenId]);

    return result.rows.length > 0 ? result.rows[0].permissions : undefined;
  } catch (err) {
    logger.error({ err }, 'Failed to read misskey access grant permissions');
    return undefined;
  }
};

const createMisskeyExtension = (deps) => {
  const isEnabled = createEnabledCheck(deps.pgPool, deps.logger);
  const compat = createMisskeyCompat({
    ...deps,
    authorizeStatusAccess: (statusId, req) => authorizeStatusAccess(deps.pgPool, statusId, req),
    loadExcludedReactionAccountIds: (viewerAccountId, reactionAccountIds) => excludedReactionAccountIds(deps.pgPool, viewerAccountId, reactionAccountIds),
    loadExcludedTimelineNote: (viewerAccountId, targets) => excludedTimelineNote(deps.pgPool, viewerAccountId, targets),
    loadGrantPermissions: (req) => loadGrantPermissions(deps.pgPool, deps.logger, req),
    isEnabled,
  });

  return { ...compat, isEnabled };
};

export { authorizeStatusAccess, createEnabledCheck, createMisskeyExtension, excludedTimelineNote, loadGrantPermissions };
