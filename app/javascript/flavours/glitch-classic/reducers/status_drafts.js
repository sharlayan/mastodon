import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import {
  STATUS_DRAFTS_FETCH_FAIL,
  STATUS_DRAFTS_FETCH_REQUEST,
  STATUS_DRAFTS_FETCH_SUCCESS,
  STATUS_DRAFT_DELETE_SUCCESS,
  STATUS_DRAFT_SAVE_SUCCESS,
} from '../actions/status_drafts';

const initialState = ImmutableMap({ items: ImmutableList(), isLoading: false });

export default function statusDrafts(state = initialState, action) {
  switch (action.type) {
  case STATUS_DRAFTS_FETCH_REQUEST:
    return state.set('isLoading', true);
  case STATUS_DRAFTS_FETCH_SUCCESS:
    return state.set('items', ImmutableList(action.drafts)).set('isLoading', false);
  case STATUS_DRAFTS_FETCH_FAIL:
    return state.set('isLoading', false);
  case STATUS_DRAFT_SAVE_SUCCESS:
    return state.update('items', items => {
      const index = items.findIndex(item => item.get('id') === action.draft.get('id'));
      return index < 0 ? items.unshift(action.draft) : items.set(index, action.draft);
    });
  case STATUS_DRAFT_DELETE_SUCCESS:
    return state.update('items', items => items.filterNot(item => item.get('id') === action.id));
  default:
    return state;
  }
}
