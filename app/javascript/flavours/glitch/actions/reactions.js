import api, { getLinks } from '../api';
import { uuid } from '../uuid';

import { importFetchedStatuses } from './importer';

export const REACTED_STATUSES_FETCH_REQUEST = 'REACTED_STATUSES_FETCH_REQUEST';
export const REACTED_STATUSES_FETCH_SUCCESS = 'REACTED_STATUSES_FETCH_SUCCESS';
export const REACTED_STATUSES_FETCH_FAIL    = 'REACTED_STATUSES_FETCH_FAIL';

export const REACTED_STATUSES_EXPAND_REQUEST = 'REACTED_STATUSES_EXPAND_REQUEST';
export const REACTED_STATUSES_EXPAND_SUCCESS = 'REACTED_STATUSES_EXPAND_SUCCESS';
export const REACTED_STATUSES_EXPAND_FAIL    = 'REACTED_STATUSES_EXPAND_FAIL';

export const REACTION_SUMMARY_FETCH_REQUEST = 'REACTION_SUMMARY_FETCH_REQUEST';
export const REACTION_SUMMARY_FETCH_SUCCESS = 'REACTION_SUMMARY_FETCH_SUCCESS';
export const REACTION_SUMMARY_FETCH_FAIL    = 'REACTION_SUMMARY_FETCH_FAIL';

export const REACTION_FILTER_SET = 'REACTION_FILTER_SET';

export function fetchReactedStatuses(name) {
  return (dispatch, getState) => {
    const selectedFilter = getState().getIn(['status_lists', 'reactionFilter'], null);
    const filter = name === undefined ? selectedFilter : name || null;

    if (filter !== selectedFilter) {
      dispatch({ type: REACTION_FILTER_SET, name: filter });
    }

    if (getState().getIn(['status_lists', 'reactions', 'isLoading'])) {
      return;
    }

    const requestId = uuid();
    dispatch(fetchReactedStatusesRequest(requestId));

    const params = {};
    if (filter) {
      params.name = filter;
    }

    api().get('/api/v1/reactions', { params }).then(response => {
      if (getState().getIn(['status_lists', 'reactions', 'requestId']) !== requestId) return;

      const next = getLinks(response).refs.find(link => link.rel === 'next');
      dispatch(importFetchedStatuses(response.data));
      dispatch(fetchReactedStatusesSuccess(response.data, next ? next.uri : null, requestId));
    }).catch(error => {
      if (getState().getIn(['status_lists', 'reactions', 'requestId']) !== requestId) return;

      dispatch(fetchReactedStatusesFail(error, requestId));
    });
  };
}

export function fetchReactedStatusesRequest(requestId) {
  return {
    type: REACTED_STATUSES_FETCH_REQUEST,
    requestId,
    skipLoading: true,
  };
}

export function fetchReactedStatusesSuccess(statuses, next, requestId) {
  return {
    type: REACTED_STATUSES_FETCH_SUCCESS,
    requestId,
    statuses,
    next,
    skipLoading: true,
  };
}

export function fetchReactedStatusesFail(error, requestId) {
  return {
    type: REACTED_STATUSES_FETCH_FAIL,
    requestId,
    error,
    skipLoading: true,
  };
}

export function expandReactedStatuses() {
  return (dispatch, getState) => {
    const url = getState().getIn(['status_lists', 'reactions', 'next'], null);

    if (url === null || getState().getIn(['status_lists', 'reactions', 'isLoading'])) {
      return;
    }

    const requestId = uuid();
    dispatch(expandReactedStatusesRequest(requestId));

    api().get(url).then(response => {
      if (getState().getIn(['status_lists', 'reactions', 'requestId']) !== requestId) return;

      const next = getLinks(response).refs.find(link => link.rel === 'next');
      dispatch(importFetchedStatuses(response.data));
      dispatch(expandReactedStatusesSuccess(response.data, next ? next.uri : null, requestId));
    }).catch(error => {
      if (getState().getIn(['status_lists', 'reactions', 'requestId']) !== requestId) return;

      dispatch(expandReactedStatusesFail(error, requestId));
    });
  };
}

export function expandReactedStatusesRequest(requestId) {
  return {
    type: REACTED_STATUSES_EXPAND_REQUEST,
    requestId,
  };
}

export function expandReactedStatusesSuccess(statuses, next, requestId) {
  return {
    type: REACTED_STATUSES_EXPAND_SUCCESS,
    requestId,
    statuses,
    next,
  };
}

export function expandReactedStatusesFail(error, requestId) {
  return {
    type: REACTED_STATUSES_EXPAND_FAIL,
    requestId,
    error,
  };
}

export function fetchReactionSummary() {
  return (dispatch) => {
    dispatch({ type: REACTION_SUMMARY_FETCH_REQUEST });

    api().get('/api/v1/reactions/summary').then(response => {
      dispatch({
        type: REACTION_SUMMARY_FETCH_SUCCESS,
        summary: response.data,
      });
    }).catch(error => {
      dispatch({
        type: REACTION_SUMMARY_FETCH_FAIL,
        error,
      });
    });
  };
}

export function setReactionFilter(name) {
  return (dispatch) => {
    dispatch({
      type: REACTION_FILTER_SET,
      name,
    });
    dispatch(fetchReactedStatuses(name));
  };
}
