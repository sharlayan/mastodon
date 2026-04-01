import api from '../api';

export const FAVORITE_EMOJIS_FETCH_REQUEST = 'FAVORITE_EMOJIS_FETCH_REQUEST';
export const FAVORITE_EMOJIS_FETCH_SUCCESS = 'FAVORITE_EMOJIS_FETCH_SUCCESS';
export const FAVORITE_EMOJIS_FETCH_FAIL    = 'FAVORITE_EMOJIS_FETCH_FAIL';
export const FAVORITE_EMOJI_ADD_REQUEST    = 'FAVORITE_EMOJI_ADD_REQUEST';
export const FAVORITE_EMOJI_ADD_SUCCESS    = 'FAVORITE_EMOJI_ADD_SUCCESS';
export const FAVORITE_EMOJI_ADD_FAIL       = 'FAVORITE_EMOJI_ADD_FAIL';
export const FAVORITE_EMOJI_REMOVE_REQUEST = 'FAVORITE_EMOJI_REMOVE_REQUEST';
export const FAVORITE_EMOJI_REMOVE_SUCCESS = 'FAVORITE_EMOJI_REMOVE_SUCCESS';
export const FAVORITE_EMOJI_REMOVE_FAIL    = 'FAVORITE_EMOJI_REMOVE_FAIL';

export function fetchFavoriteEmojis() {
  return (dispatch) => {
    dispatch({ type: FAVORITE_EMOJIS_FETCH_REQUEST, skipLoading: true });

    api().get('/api/v1/favorite_emojis').then(response => {
      dispatch({
        type: FAVORITE_EMOJIS_FETCH_SUCCESS,
        favorite_emojis: response.data,
        skipLoading: true,
      });
    }).catch(error => {
      dispatch({ type: FAVORITE_EMOJIS_FETCH_FAIL, error, skipLoading: true });
    });
  };
}

export function addFavoriteEmoji(name, emoji_type) {
  return (dispatch) => {
    dispatch({
      type: FAVORITE_EMOJI_ADD_REQUEST,
      name,
      emoji_type,
      skipLoading: true,
    });

    api().post('/api/v1/favorite_emojis', { name, emoji_type }).then(response => {
      dispatch({
        type: FAVORITE_EMOJI_ADD_SUCCESS,
        favorite_emoji: response.data,
        skipLoading: true,
      });
    }).catch(error => {
      dispatch({
        type: FAVORITE_EMOJI_ADD_FAIL,
        name,
        error,
        skipLoading: true,
      });
    });
  };
}

export function removeFavoriteEmoji(name, emoji_type, position) {
  return (dispatch) => {
    dispatch({
      type: FAVORITE_EMOJI_REMOVE_REQUEST,
      name,
      emoji_type,
      position,
      skipLoading: true,
    });

    api().delete(`/api/v1/favorite_emojis/${encodeURIComponent(name)}`).then(() => {
      dispatch({
        type: FAVORITE_EMOJI_REMOVE_SUCCESS,
        name,
        skipLoading: true,
      });
    }).catch(error => {
      dispatch({
        type: FAVORITE_EMOJI_REMOVE_FAIL,
        name,
        emoji_type,
        position,
        error,
        skipLoading: true,
      });
    });
  };
}
