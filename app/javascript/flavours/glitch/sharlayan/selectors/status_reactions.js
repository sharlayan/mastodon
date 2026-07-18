const getReactionUsers = (state, id) => {
  const reactions = state.getIn(['statuses', id, 'reactions']);
  if (!reactions) return null;

  return reactions.map(reaction => {
    const users = reaction.get('users');
    if (!users) return null;
    return users
      .map(user => user && state.getIn(['accounts', user.get('id')]))
      .filter(account => !!account);
  });
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
