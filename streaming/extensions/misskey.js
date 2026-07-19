import { createMisskeyCompat } from '../misskey_compat.js';

const createEnabledCheck = (pgPool, logger, now = Date.now) => {
  let setting = { value: false, checkedAt: 0 };

  return async () => {
    const checkedAt = now();
    if (checkedAt - setting.checkedAt < 15000) return setting.value;

    try {
      const result = await pgPool.query("SELECT value FROM settings WHERE var = 'misskey_compat_enabled' LIMIT 1");
      const enabled = result.rows.length > 0 && result.rows[0].value === "--- true\n";
      setting = { value: enabled, checkedAt };
      return enabled;
    } catch (err) {
      logger.error({ err }, 'Failed to read misskey_compat_enabled setting');
      return false;
    }
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

const createMisskeyExtension = (deps) => {
  const isEnabled = createEnabledCheck(deps.pgPool, deps.logger);
  const compat = createMisskeyCompat({
    ...deps,
    authorizeStatusAccess: (statusId, req) => authorizeStatusAccess(deps.pgPool, statusId, req),
    isEnabled,
  });

  return { ...compat, isEnabled };
};

export { authorizeStatusAccess, createEnabledCheck, createMisskeyExtension };
