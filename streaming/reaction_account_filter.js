'use strict';

const reactionAccountIds = (payload) => {
  if (!Array.isArray(payload?.reactions)) return [];

  return [...new Set(payload.reactions.flatMap((reaction) => (
    Array.isArray(reaction?.account_ids) ? reaction.account_ids.map(String) : []
  )))];
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

  return filtered;
};

export { filterReactionAccounts, reactionAccountIds };
