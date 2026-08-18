const reactionUsersCache = new WeakMap();

const getReactionUsers = (state, id) => {
  const reactions = state.getIn(['statuses', id, 'reactions']);
  if (!reactions) return null;

  const accounts = state.get('accounts');
  let accountsCache = reactionUsersCache.get(reactions);
  if (!accountsCache) {
    accountsCache = new WeakMap();
    reactionUsersCache.set(reactions, accountsCache);
  }

  const cached = accountsCache.get(accounts);
  if (cached) return cached;

  const resolved = reactions.map(reaction => {
    const users = reaction.get('users');
    if (!users) return null;
    return users
      .map(user => user && (accounts.get(user.get('id')) || user))
      .filter(account => !!account);
  });

  accountsCache.set(accounts, resolved);
  return resolved;
};

export const sharlayanStatusInputSelectors = [
  (state, { id }) => getReactionUsers(state, id),
  (state, { id }) => {
    const reblogId = state.getIn(['statuses', id, 'reblog']);
    return reblogId ? getReactionUsers(state, reblogId) : null;
  },
];

export const applySharlayanStatusReactions = (map, statusBase, statusReblog, reactedUsers, reactedUsersReblog) => {
  let reactions = statusReblog
    ? statusReblog.get('reactions')
    : statusBase.get('reactions');

  const usersPerReaction = statusReblog
    ? reactedUsersReblog
    : reactedUsers;

  if (reactions && usersPerReaction) {
    reactions = reactions.map((reaction, i) => {
      const resolvedUsers = usersPerReaction.get(i);
      if (resolvedUsers) {
        return reaction.set('users', resolvedUsers);
      }
      return reaction;
    });
  }

  if (statusReblog) {
    map.set('reblog', statusReblog.set('reactions', reactions));
  } else {
    map.set('reactions', reactions);
  }
};
