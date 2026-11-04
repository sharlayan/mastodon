import { createMisskeyCompat } from '../misskey_compat.js';
import { excludedReactionAccountIds } from '../reaction_account_filter.js';

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

const loadGrantPermissions = async (pgPool, logger, req, failClosed = false) => {
  if (!req.accessTokenId) return undefined;

  try {
    const result = await pgPool.query('SELECT permissions FROM misskey_access_grants WHERE access_token_id = $1 LIMIT 1', [req.accessTokenId]);

    return result.rows.length > 0 ? result.rows[0].permissions : undefined;
  } catch (err) {
    logger.error({ err }, 'Failed to read misskey access grant permissions');
    return failClosed ? [] : undefined;
  }
};

const validChatId = (value) => typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value) && BigInt(value) <= 9223372036854775807n;

const isChatEnabled = async (pgPool) => {
  const result = await pgPool.query("SELECT var, value FROM settings WHERE var IN ('chat_enabled', 'misskey_compat_enabled')");
  return ['chat_enabled', 'misskey_compat_enabled'].every((name) => result.rows.some((row) => row.var === name && row.value === '--- true\n'));
};

const createChatEnabledCheck = (pgPool, logger, now = Date.now) => {
  let setting = { value: false, checkedAt: 0 };
  let refresh;

  return async () => {
    if (now() - setting.checkedAt < 15000) return setting.value;
    if (refresh) return refresh;

    refresh = isChatEnabled(pgPool)
      .then((enabled) => {
        setting = { value: enabled, checkedAt: now() };
        return enabled;
      })
      .catch((err) => {
        logger.error({ err }, 'Failed to read chat settings');
        setting = { value: false, checkedAt: now() };
        return false;
      })
      .finally(() => {
        refresh = undefined;
      });

    return refresh;
  };
};

const CHAT_TARGET_SQL = `(
  ($3 = 'chatRoom' AND conversation.conversation_type = 1 AND conversation.id = $2::bigint)
  OR ($3 = 'chatUser' AND conversation.conversation_type = 0 AND EXISTS (
    SELECT 1 FROM chat_memberships peer
    WHERE peer.chat_conversation_id = conversation.id AND peer.account_id = $2::bigint
  ))
  OR $3 = 'main'
)`;

const authorizeChatAccess = async (pgPool, channel, targetId, req, event) => {
  if (!validChatId(req.accountId) || !['chatUser', 'chatRoom', 'main'].includes(channel)) return false;
  if (channel !== 'main' && (!validChatId(targetId) || channel === 'chatUser' && targetId === req.accountId)) return false;
  if (!event && channel === 'main') return true;
  if (!event && channel === 'chatUser') {
    const result = await pgPool.query('SELECT id FROM accounts WHERE id = $1 AND suspended_at IS NULL LIMIT 1', [targetId]);
    return result.rows.length > 0;
  }

  const conversationId = event?.conversationId ?? targetId;
  if (!validChatId(conversationId) || event?.messageId != null && !validChatId(event.messageId)) return false;
  const result = await pgPool.query(`
    SELECT conversation.id FROM chat_conversations conversation
    JOIN chat_memberships membership ON membership.chat_conversation_id = conversation.id
    WHERE membership.account_id = $1 AND conversation.id = $4 AND ${CHAT_TARGET_SQL}
      AND ($5::bigint IS NULL OR EXISTS (
        SELECT 1 FROM chat_messages message
        WHERE message.id = $5 AND message.chat_conversation_id = conversation.id
          AND ($6::boolean OR ((message.account_id != $1 OR message.hidden_at IS NULL) AND message.deleted_at IS NULL))
      )) LIMIT 1
  `, [req.accountId, targetId ?? null, channel, conversationId, event?.messageId ?? null, event?.type === 'deleted']);
  return result.rows.length > 0;
};

const markChatRead = async (pgPool, channel, targetId, req, messageId) => {
  if (!['chatUser', 'chatRoom'].includes(channel) || !validChatId(req.accountId) || !validChatId(targetId) || !validChatId(messageId)) return false;
  if (channel === 'chatUser' && targetId === req.accountId) return false;
  const result = await pgPool.query(`
    UPDATE chat_memberships membership
    SET last_read_message_id = message.id, updated_at = CURRENT_TIMESTAMP
    FROM chat_conversations conversation, chat_messages message
    WHERE membership.account_id = $1 AND membership.chat_conversation_id = conversation.id
      AND message.chat_conversation_id = conversation.id AND message.id = $4
      AND (message.account_id != $1 OR message.hidden_at IS NULL)
      AND (membership.last_read_message_id IS NULL OR membership.last_read_message_id < message.id)
      AND ${CHAT_TARGET_SQL}
    RETURNING membership.last_read_message_id
  `, [req.accountId, targetId, channel, messageId]);
  return result.rows.length > 0;
};

const createMisskeyExtension = (deps) => {
  const isEnabled = createEnabledCheck(deps.pgPool, deps.logger);
  const compat = createMisskeyCompat({
    ...deps,
    authorizeStatusAccess: (statusId, req) => authorizeStatusAccess(deps.pgPool, statusId, req),
    loadExcludedReactionAccountIds: (viewerAccountId, reactionAccountIds) => excludedReactionAccountIds(deps.pgPool, viewerAccountId, reactionAccountIds),
    loadGrantPermissions: (req) => loadGrantPermissions(deps.pgPool, deps.logger, req),
    loadChatGrantPermissions: (req) => loadGrantPermissions(deps.pgPool, deps.logger, req, true),
    isChatEnabled: createChatEnabledCheck(deps.pgPool, deps.logger),
    authorizeChatAccess: (channel, targetId, req, event) => authorizeChatAccess(deps.pgPool, channel, targetId, req, event),
    markChatRead: (channel, targetId, req, messageId) => markChatRead(deps.pgPool, channel, targetId, req, messageId),
    isEnabled,
  });

  return { ...compat, isEnabled };
};

export { authorizeChatAccess, authorizeStatusAccess, createChatEnabledCheck, createEnabledCheck, createMisskeyExtension, isChatEnabled, loadGrantPermissions, markChatRead };
