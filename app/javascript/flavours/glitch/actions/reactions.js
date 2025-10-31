import api, { getLinks } from '../api';

import { importFetchedStatuses } from './importer';

export const REACTED_STATUSES_FETCH_REQUEST = 'REACTED_STATUSES_FETCH_REQUEST';
export const REACTED_STATUSES_FETCH_SUCCESS = 'REACTED_STATUSES_FETCH_SUCCESS';
export const REACTED_STATUSES_FETCH_FAIL    = 'REACTED_STATUSES_FETCH_FAIL';

export const REACTED_STATUSES_EXPAND_REQUEST = 'REACTED_STATUSES_EXPAND_REQUEST';
export const REACTED_STATUSES_EXPAND_SUCCESS = 'REACTED_STATUSES_EXPAND_SUCCESS';
export const REACTED_STATUSES_EXPAND_FAIL    = 'REACTED_STATUSES_EXPAND_FAIL';

export const fetchReactedStatuses = () => (dispatch, getState) => {
  if (getState().getIn(['status_lists', 'reactions', 'isLoading'])) {
    return;
  }

  dispatch(fetchReactedStatusesRequest());

  api(getState).get('/api/v1/reactions').then(response => {
    const next = getLinks(response).refs.find(link => link.rel === 'next');
    dispatch(importFetchedStatuses(response.data));
    dispatch(fetchReactedStatusesSuccess(response.data, next ? next.uri : null));
  }).catch(error => {
    dispatch(fetchReactedStatusesFail(error));
  });
};

export const fetchReactedStatusesRequest = () => ({
  type: REACTED_STATUSES_FETCH_REQUEST,
  skipLoading: true,
})

export const fetchReactedStatusesSuccess = (statuses, next) => ({
  type: REACTED_STATUSES_FETCH_SUCCESS,
  statuses,
  next,
  skipLoading: true,
})

export const fetchReactedStatusesFail = (error) => ({
  type: REACTED_STATUSES_FETCH_FAIL,
  error,
  skipLoading: true,
});

export const expandReactedStatuses = () => (dispatch, getState) => {
  const url = getState().getIn(['status_lists', 'reactions', 'next'], null);

  if (url === null || getState().getIn(['status_lists', 'reactions', 'isLoading'])) {
    return;
  }

  dispatch(expandReactedStatusesRequest());

  api(getState).get(url).then(response => {
    const next = getLinks(response).refs.find(link => link.rel === 'next');
    dispatch(importFetchedStatuses(response.data));
    dispatch(expandReactedStatusesSuccess(response.data, next ? next.uri : null));
  }).catch(error => {
    dispatch(expandReactedStatusesFail(error));
  });
};

export const expandReactedStatusesRequest = () => ({
  type: REACTED_STATUSES_EXPAND_REQUEST,
})

export const expandReactedStatusesSuccess = (statuses, next) => ({
  type: REACTED_STATUSES_EXPAND_SUCCESS,
  statuses,
  next,
})

export const expandReactedStatusesFail = (error) => ({
  type: REACTED_STATUSES_EXPAND_FAIL,
  error,
})
