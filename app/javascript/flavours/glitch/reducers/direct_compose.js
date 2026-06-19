import { Map as ImmutableMap, List as ImmutableList, fromJS } from 'immutable';

import {
  DIRECT_COMPOSE_CHANGE,
  DIRECT_COMPOSE_RESET,
  DIRECT_COMPOSE_SET_REPLY,
  DIRECT_COMPOSE_CLEAR_REPLY,
  DIRECT_COMPOSE_SUBMIT_REQUEST,
  DIRECT_COMPOSE_SUBMIT_SUCCESS,
  DIRECT_COMPOSE_SUBMIT_FAIL,
  DIRECT_COMPOSE_UPLOAD_REQUEST,
  DIRECT_COMPOSE_UPLOAD_PROGRESS,
  DIRECT_COMPOSE_UPLOAD_SUCCESS,
  DIRECT_COMPOSE_UPLOAD_FAIL,
  DIRECT_COMPOSE_UPLOAD_REMOVE,
} from '../actions/direct_compose';

const initialThread = ImmutableMap({
  text: '',
  media: ImmutableList(),
  is_uploading: false,
  is_submitting: false,
  progress: 0,
  in_reply_to_id: null,
});

const initialState = ImmutableMap();

const thread = (state, conversationId) => state.get(conversationId, initialThread);

const updateThread = (state, conversationId, updater) =>
  state.set(conversationId, updater(thread(state, conversationId)));

export default function direct_compose(state = initialState, action) {
  switch (action.type) {
  case DIRECT_COMPOSE_CHANGE:
    return updateThread(state, action.conversationId, t => t.set('text', action.text));
  case DIRECT_COMPOSE_RESET:
    return state.set(action.conversationId, initialThread);
  case DIRECT_COMPOSE_SET_REPLY:
    return updateThread(state, action.conversationId, t => t.set('in_reply_to_id', action.statusId));
  case DIRECT_COMPOSE_CLEAR_REPLY:
    return updateThread(state, action.conversationId, t => t.set('in_reply_to_id', null));
  case DIRECT_COMPOSE_SUBMIT_REQUEST:
    return updateThread(state, action.conversationId, t => t.set('is_submitting', true));
  case DIRECT_COMPOSE_SUBMIT_SUCCESS:
    return state.set(action.conversationId, initialThread);
  case DIRECT_COMPOSE_SUBMIT_FAIL:
    return updateThread(state, action.conversationId, t => t.set('is_submitting', false));
  case DIRECT_COMPOSE_UPLOAD_REQUEST:
    return updateThread(state, action.conversationId, t => t.set('is_uploading', true).set('progress', 0));
  case DIRECT_COMPOSE_UPLOAD_PROGRESS:
    return updateThread(state, action.conversationId, t => t.set('progress', action.total ? Math.round((action.loaded / action.total) * 100) : 0));
  case DIRECT_COMPOSE_UPLOAD_SUCCESS:
    return updateThread(state, action.conversationId, t => t.set('is_uploading', false).set('progress', 0).update('media', media => media.push(fromJS(action.media))));
  case DIRECT_COMPOSE_UPLOAD_FAIL:
    return updateThread(state, action.conversationId, t => t.set('is_uploading', false).set('progress', 0));
  case DIRECT_COMPOSE_UPLOAD_REMOVE:
    return updateThread(state, action.conversationId, t => t.update('media', media => media.filterNot(item => item.get('id') === action.mediaId)));
  default:
    return state;
  }
}
