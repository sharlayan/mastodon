import api, { getLinks } from '../api';

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
    if (getState().getIn(['status_lists', 'reactions', 'isLoading'])) {
      return;
    }

    dispatch(fetchReactedStatusesRequest());

    const params = {};
    if (name) {
      params.name = name;
    }

    api().get('/api/v1/reactions', { params }).then(response => {
      const next = getLinks(response).refs.find(link => link.rel === 'next');
      dispatch(importFetchedStatuses(response.data));
      dispatch(fetchReactedStatusesSuccess(response.data, next ? next.uri : null));
    }).catch(error => {
      dispatch(fetchReactedStatusesFail(error));
    });
  };
}

export function fetchReactedStatusesRequest() {
  return {
    type: REACTED_STATUSES_FETCH_REQUEST,
    skipLoading: true,
  };
}

export function fetchReactedStatusesSuccess(statuses, next) {
  return {
    type: REACTED_STATUSES_FETCH_SUCCESS,
    statuses,
    next,
    skipLoading: true,
  };
}

export function fetchReactedStatusesFail(error) {
  return {
    type: REACTED_STATUSES_FETCH_FAIL,
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

    dispatch(expandReactedStatusesRequest());

    api().get(url).then(response => {
      const next = getLinks(response).refs.find(link => link.rel === 'next');
      dispatch(importFetchedStatuses(response.data));
      dispatch(expandReactedStatusesSuccess(response.data, next ? next.uri : null));
    }).catch(error => {
      dispatch(expandReactedStatusesFail(error));
    });
  };
}

export function expandReactedStatusesRequest() {
  return {
    type: REACTED_STATUSES_EXPAND_REQUEST,
  };
}

export function expandReactedStatusesSuccess(statuses, next) {
  return {
    type: REACTED_STATUSES_EXPAND_SUCCESS,
    statuses,
    next,
  };
}

export function expandReactedStatusesFail(error) {
  return {
    type: REACTED_STATUSES_EXPAND_FAIL,
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
