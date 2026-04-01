import { List as ImmutableList, Map as ImmutableMap, fromJS } from 'immutable';

import {
  FAVORITE_EMOJIS_FETCH_SUCCESS,
  FAVORITE_EMOJI_ADD_REQUEST,
  FAVORITE_EMOJI_ADD_FAIL,
  FAVORITE_EMOJI_REMOVE_REQUEST,
  FAVORITE_EMOJI_REMOVE_FAIL,
} from '../actions/favorite_emojis';

const initialState = ImmutableList([]);

export default function favorite_emojis(state = initialState, action) {
  switch (action.type) {
  case FAVORITE_EMOJIS_FETCH_SUCCESS:
    return fromJS(action.favorite_emojis);
  case FAVORITE_EMOJI_ADD_REQUEST:
    return state.push(ImmutableMap({
      name: action.name,
      emoji_type: action.emoji_type,
      position: state.size,
    }));
  case FAVORITE_EMOJI_ADD_FAIL:
    return state.filterNot(e => e.get('name') === action.name);
  case FAVORITE_EMOJI_REMOVE_REQUEST:
    return state.filterNot(e => e.get('name') === action.name);
  case FAVORITE_EMOJI_REMOVE_FAIL:
    return state.push(ImmutableMap({
      name: action.name,
      emoji_type: action.emoji_type,
      position: action.position,
    }));
  default:
    return state;
  }
}
