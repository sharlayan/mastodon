import { createSelector } from '@reduxjs/toolkit';
import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { me } from '../initial_state';

import { getFilters } from './filters';

export { makeGetAccount } from "./accounts";
export { getStatusList } from "./statuses";

const getStatusInputSelectors = [
  (state, { id }) => state.getIn(['statuses', id]),
  (state, { id }) => state.getIn(['statuses', state.getIn(['statuses', id, 'reblog'])]),
  (state, { id }) => state.getIn(['accounts', state.getIn(['statuses', id, 'account'])]),
  (state, { id }) => state.getIn(['accounts', state.getIn(['statuses', state.getIn(['statuses', id, 'reblog']), 'account'])]),
  (state, { id }) => getReactionUsers(state, id),
  (state, { id }) => {
    const reblogId = state.getIn(['statuses', id, 'reblog']);
    return reblogId ? getReactionUsers(state, reblogId) : null;
  },
  getFilters,
  (_, { contextType }) => ['detailed', 'bookmarks', 'favourites', 'search'].includes(contextType),
];

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

function getStatusResultFunction(
  statusBase,
  statusReblog,
  accountBase,
  accountReblog,
  reactedUsers,
  reactedUsersReblog,
  filters,
  warnInsteadOfHide
) {
  if (!statusBase) {
    return {
      status: null,
      loadingState: 'not-found',
    };
  }

  // When a status is loading, a `isLoading` property is set
  // A status can be loading because it is not known yet (in which case it will only contain `isLoading`)
  // or because it is being re-fetched; in the latter case, `visibility` will always be set to a non-empty
  // string.
  if (statusBase.get('isLoading') && !statusBase.get('visibility')) {
    return {
      status: null,
      loadingState: 'loading',
    }
  }

  let filtered = false;
  let mediaFiltered = false;
  if ((accountReblog || accountBase).get('id') !== me && filters) {
    let filterResults = statusReblog?.get('filtered') || statusBase.get('filtered') || ImmutableList();
    if (!warnInsteadOfHide && filterResults.some((result) => filters.getIn([result.get('filter'), 'filter_action']) === 'hide')) {
      return {
        status: null,
        loadingState: 'filtered',
      }
    }

    let mediaFilters = filterResults.filter(result => filters.getIn([result.get('filter'), 'filter_action']) === 'blur');
    if (!mediaFilters.isEmpty()) {
      mediaFiltered = mediaFilters.map(result => filters.getIn([result.get('filter'), 'title']));
    }

    filterResults = filterResults.filter(result => filters.has(result.get('filter')) && filters.getIn([result.get('filter'), 'filter_action']) !== 'blur');
    if (!filterResults.isEmpty()) {
      filtered = filterResults.map(result => filters.getIn([result.get('filter'), 'title']));
    }
  }

  if (statusReblog) {
    statusReblog = statusReblog.set('account', accountReblog);
    statusReblog = statusReblog.set('matched_filters', filtered);
  } else {
    statusReblog = null;
  }

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

  return {
    status: statusBase.withMutations(map => {
      map.set('reblog', statusReblog);
      map.set('account', accountBase);
      map.set('matched_filters', filtered);
      map.set('matched_media_filters', mediaFiltered);

      if (!statusReblog) {
        map.set('reactions', reactions);
      }
    }),
    loadingState: statusBase.get('isLoading') ? 'loading' : 'complete'
  };
}

export const makeGetStatus = () => {
  return createSelector(
    getStatusInputSelectors,
    (...args) => {
      const {status} = getStatusResultFunction(...args);
      return status
    },
  );
};

/**
 * This selector extends the `makeGetStatus` with a more detailed
 * `loadingState`, which is useful to find out why `null` is returned
 * for the `status` field
 */
export const makeGetStatusWithExtraInfo = () => {
  return createSelector(
    getStatusInputSelectors,
    getStatusResultFunction,
  );
};

export const makeGetPictureInPicture = () => {
  return createSelector([
    (state, { id }) => state.picture_in_picture.statusId === id,
    (state) => state.getIn(['meta', 'layout']) !== 'mobile',
  ], (inUse, available) => ImmutableMap({
    inUse: inUse && available,
    available,
  }));
};

export const makeGetNotification = () => createSelector([
  (_, base)             => base,
  (state, _, accountId) => state.getIn(['accounts', accountId]),
], (base, account) => base.set('account', account));

export const makeGetReport = () => createSelector([
  (_, base) => base,
  (state, _, targetAccountId) => state.getIn(['accounts', targetAccountId]),
], (base, targetAccount) => base.set('target_account', targetAccount));
