const reactionUsersCache = new WeakMap();

const resolveReactionUser = (accounts, user) => user && (accounts.get(user.get('id')) || user);

const resolveReactionUsers = (reactions, accounts) => reactions.map(reaction => {
  const users = reaction.get('users');
  if (!users) return null;
  return users
    .map(user => resolveReactionUser(accounts, user))
    .filter(account => !!account);
});

const sameReactionUsers = (reactions, accounts, previous) => reactions.every((reaction, index) => {
  const users = reaction.get('users');
  const previousUsers = previous.get(index);
  if (!users) return !previousUsers;
  if (!previousUsers) return false;

  let position = 0;
  for (const user of users) {
    const account = resolveReactionUser(accounts, user);
    if (!account) continue;
    if (previousUsers.get(position) !== account) return false;
    position += 1;
  }

  return position === previousUsers.size;
});

const getReactionUsers = (state, id) => {
  const reactions = state.getIn(['statuses', id, 'reactions']);
  if (!reactions) return null;

  const accounts = state.get('accounts');
  const cached = reactionUsersCache.get(reactions);

  if (cached) {
    if (cached.accounts === accounts) return cached.resolved;

    if (sameReactionUsers(reactions, accounts, cached.resolved)) {
      cached.accounts = accounts;
      return cached.resolved;
    }
  }

  const resolved = resolveReactionUsers(reactions, accounts);
  reactionUsersCache.set(reactions, { accounts, resolved });
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
