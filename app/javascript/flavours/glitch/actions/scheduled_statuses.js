import { Map as ImmutableMap, List as ImmutableList, fromJS } from 'immutable';

import api from '../api';

import { showAlert } from './alerts';
import { ensureComposeIsVisible } from './compose';

export const SCHEDULED_STATUSES_FETCH_REQUEST = 'SCHEDULED_STATUSES_FETCH_REQUEST';
export const SCHEDULED_STATUSES_FETCH_SUCCESS = 'SCHEDULED_STATUSES_FETCH_SUCCESS';
export const SCHEDULED_STATUSES_FETCH_FAIL = 'SCHEDULED_STATUSES_FETCH_FAIL';

export const SCHEDULED_STATUS_DELETE_REQUEST = 'SCHEDULED_STATUS_DELETE_REQUEST';
export const SCHEDULED_STATUS_DELETE_SUCCESS = 'SCHEDULED_STATUS_DELETE_SUCCESS';
export const SCHEDULED_STATUS_DELETE_FAIL = 'SCHEDULED_STATUS_DELETE_FAIL';

export const SCHEDULED_STATUS_UPDATE_REQUEST = 'SCHEDULED_STATUS_UPDATE_REQUEST';
export const SCHEDULED_STATUS_UPDATE_SUCCESS = 'SCHEDULED_STATUS_UPDATE_SUCCESS';
export const SCHEDULED_STATUS_UPDATE_FAIL = 'SCHEDULED_STATUS_UPDATE_FAIL';

export const SCHEDULED_STATUS_ADD = 'SCHEDULED_STATUS_ADD';

export function fetchScheduledStatuses() {
  return (dispatch) => {
    dispatch({ type: SCHEDULED_STATUSES_FETCH_REQUEST });

    api().get('/api/v1/scheduled_statuses')
      .then(({ data }) => {
        dispatch({
          type: SCHEDULED_STATUSES_FETCH_SUCCESS,
          statuses: data.map(s => fromJS(s)),
        });
      })
      .catch((err) => {
        dispatch({ type: SCHEDULED_STATUSES_FETCH_FAIL });
      });
  };
}

export function deleteScheduledStatus(id) {
  return (dispatch) => {
    dispatch({ type: SCHEDULED_STATUS_DELETE_REQUEST, id });

    api().delete(`/api/v1/scheduled_statuses/${id}`)
      .then(() => {
        dispatch({ type: SCHEDULED_STATUS_DELETE_SUCCESS, id });
      })
      .catch((err) => {
        dispatch({ type: SCHEDULED_STATUS_DELETE_FAIL, id });
      });
  };
}

export function updateScheduledStatus(id, scheduledAt) {
  return (dispatch) => {
    dispatch({ type: SCHEDULED_STATUS_UPDATE_REQUEST, id });

    api().put(`/api/v1/scheduled_statuses/${id}`, { scheduled_at: scheduledAt })
      .then(({ data }) => {
        dispatch({
          type: SCHEDULED_STATUS_UPDATE_SUCCESS,
          status: fromJS(data),
        });
      })
      .catch((err) => {
        dispatch({ type: SCHEDULED_STATUS_UPDATE_FAIL, id });
      });
  };
}

export function setComposeToScheduledStatus(scheduledStatus) {
  return (dispatch, getState) => {
    dispatch({
      type: 'COMPOSE_SET_SCHEDULED',
      scheduledStatus,
      maxOptions: getState().server.getIn(['server', 'configuration', 'polls', 'max_options']),
    });
    ensureComposeIsVisible(getState);
  };
}

export function addScheduledStatus(status) {
  return (dispatch) => {
    dispatch({
      type: SCHEDULED_STATUS_ADD,
      status: typeof status.get === 'function' ? status : fromJS(status),
    });
  };
}
