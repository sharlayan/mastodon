'use strict';

const reactionAccountIds = (payload) => {
  if (!Array.isArray(payload?.reactions)) return [];

  return [...new Set(payload.reactions.flatMap((reaction) => (
    Array.isArray(reaction?.account_ids) ? reaction.account_ids.map(String) : []
  )))];
};

const EXCLUSION_CACHE_TTL = 5000;
const EXCLUSION_CACHE_MAX_ENTRIES = 5000;

const exclusionCache = new Map();

const exclusionCacheKey = (viewerAccountId, candidateAccountIds) => `${viewerAccountId}:${candidateAccountIds.join(',')}`;

const pruneExclusionCache = (checkedAt) => {
  for (const [key, entry] of exclusionCache) {
    if (checkedAt - entry.checkedAt >= EXCLUSION_CACHE_TTL) exclusionCache.delete(key);
  }

  while (exclusionCache.size > EXCLUSION_CACHE_MAX_ENTRIES) {
    exclusionCache.delete(exclusionCache.keys().next().value);
  }
};

const clearExcludedReactionAccountIdsCache = () => exclusionCache.clear();

const excludedReactionAccountIds = (pgPool, viewerAccountId, candidateAccountIds, now = Date.now) => {
  if (candidateAccountIds.length === 0) return Promise.resolve([]);

  const key = exclusionCacheKey(viewerAccountId, candidateAccountIds);
  const checkedAt = now();
  const cached = exclusionCache.get(key);

  if (cached && checkedAt - cached.checkedAt < EXCLUSION_CACHE_TTL) return cached.promise;

  const promise = queryExcludedReactionAccountIds(pgPool, viewerAccountId, candidateAccountIds);

  exclusionCache.set(key, { checkedAt, promise });
  pruneExclusionCache(checkedAt);

  promise.catch(() => {
    if (exclusionCache.get(key)?.promise === promise) exclusionCache.delete(key);
  });

  return promise;
};

const queryExcludedReactionAccountIds = async (pgPool, viewerAccountId, candidateAccountIds) => {
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

export { clearExcludedReactionAccountIdsCache, excludedReactionAccountIds, filterReactionAccounts, filterReactionPayload, reactionAccountIds };
