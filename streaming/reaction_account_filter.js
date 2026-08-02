'use strict';

const reactionAccountIds = (payload) => {
  if (!Array.isArray(payload?.reactions)) return [];

  return [...new Set(payload.reactions.flatMap((reaction) => (
    Array.isArray(reaction?.account_ids) ? reaction.account_ids.map(String) : []
  )))];
};

const excludedReactionAccountIds = async (pgPool, viewerAccountId, candidateAccountIds) => {
  if (candidateAccountIds.length === 0) return [];

  const { rows } = await pgPool.query(`SELECT target_account_id AS id
                                       FROM mutes
                                       WHERE account_id = $1
                                         AND target_account_id = ANY($2::bigint[])
                                       UNION
                                       SELECT target_account_id AS id
                                       FROM blocks
                                       WHERE account_id = $1
                                         AND target_account_id = ANY($2::bigint[])
                                       UNION
                                       SELECT account_id AS id
                                       FROM blocks
                                       WHERE target_account_id = $1
                                         AND account_id = ANY($2::bigint[])`, [viewerAccountId, candidateAccountIds]);

  return rows.map(({ id }) => String(id));
};

const filterReactionAccounts = (payload, excludedAccountIds) => {
  if (!Array.isArray(payload?.reactions) || excludedAccountIds.length === 0) return payload;

  const excluded = new Set(excludedAccountIds.map(String));
  const filtered = structuredClone(payload);

  filtered.reactions = filtered.reactions.filter((reaction) => {
    if (!Array.isArray(reaction.account_ids)) return true;

    reaction.account_ids = reaction.account_ids.filter((id) => !excluded.has(String(id)));
    reaction.count = reaction.account_ids.length;

    if (Array.isArray(reaction.users)) {
      reaction.users = reaction.users.filter((account) => !excluded.has(String(account?.id)));
    }

    return reaction.count > 0;
  });

  if (typeof filtered.reactions_count === 'number') {
    filtered.reactions_count = filtered.reactions.reduce((sum, reaction) => sum + reaction.count, 0);
  }

  return filtered;
};

const filterReactionPayload = async (pgPool, viewerAccountId, payload) => {
  const accountIds = reactionAccountIds(payload);
  const excludedAccountIds = await excludedReactionAccountIds(pgPool, viewerAccountId, accountIds);

  return filterReactionAccounts(payload, excludedAccountIds);
};

export { excludedReactionAccountIds, filterReactionAccounts, filterReactionPayload, reactionAccountIds };
