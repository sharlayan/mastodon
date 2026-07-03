import { Map as ImmutableMap, List as ImmutableList } from 'immutable';

import {
  SCHEDULED_STATUSES_FETCH_REQUEST,
  SCHEDULED_STATUSES_FETCH_SUCCESS,
  SCHEDULED_STATUSES_FETCH_FAIL,
  SCHEDULED_STATUS_DELETE_REQUEST,
  SCHEDULED_STATUS_DELETE_SUCCESS,
  SCHEDULED_STATUS_DELETE_FAIL,
  SCHEDULED_STATUS_UPDATE_REQUEST,
  SCHEDULED_STATUS_UPDATE_SUCCESS,
  SCHEDULED_STATUS_UPDATE_FAIL,
  SCHEDULED_STATUS_ADD,
} from '../actions/scheduled_statuses';

const initialState = ImmutableMap({
  items: ImmutableList(),
  isLoading: false,
});

export default function scheduledStatuses(state = initialState, action) {
  switch (action.type) {
  case SCHEDULED_STATUSES_FETCH_REQUEST:
    return state.set('isLoading', true);
  case SCHEDULED_STATUSES_FETCH_SUCCESS:
    return state
      .set('items', ImmutableList(action.statuses))
      .set('isLoading', false);
  case SCHEDULED_STATUSES_FETCH_FAIL:
    return state.set('isLoading', false);
  case SCHEDULED_STATUS_DELETE_REQUEST:
    return state;
  case SCHEDULED_STATUS_DELETE_SUCCESS:
    return state.update('items', list =>
      list.filterNot(item => item.get('id') === action.id));
  case SCHEDULED_STATUS_DELETE_FAIL:
    return state;
  case SCHEDULED_STATUS_UPDATE_REQUEST:
    return state;
  case SCHEDULED_STATUS_UPDATE_SUCCESS:
    return state.update('items', list => {
      const idx = list.findIndex(item => item.get('id') === action.status.get('id'));
      if (idx === -1) return list.push(action.status);
      return list.set(idx, action.status);
    });
  case SCHEDULED_STATUS_UPDATE_FAIL:
    return state;
  case SCHEDULED_STATUS_ADD:
    return state.update('items', list => {
      const id = action.status.get('id');
      if (list.some(item => item.get('id') === id)) return list;
      return list.unshift(action.status);
    });
  default:
    return state;
  }
}
