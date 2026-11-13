import api from '../api';

export const CIRCLE_FETCH_REQUEST = 'CIRCLE_FETCH_REQUEST';
export const CIRCLE_FETCH_SUCCESS = 'CIRCLE_FETCH_SUCCESS';
export const CIRCLE_FETCH_FAIL    = 'CIRCLE_FETCH_FAIL';

export const CIRCLE_DELETE_REQUEST = 'CIRCLE_DELETE_REQUEST';
export const CIRCLE_DELETE_SUCCESS = 'CIRCLE_DELETE_SUCCESS';
export const CIRCLE_DELETE_FAIL    = 'CIRCLE_DELETE_FAIL';

export * from './circles_typed';

export const fetchCircle = id => (dispatch, getState) => {
  if (getState().getIn(['circles', id])) {
    return;
  }

  dispatch(fetchCircleRequest(id));

  api().get(`/api/v1/circles/${id}`)
    .then(({ data }) => dispatch(fetchCircleSuccess(data)))
    .catch(err => dispatch(fetchCircleFail(id, err)));
};

export const fetchCircleRequest = id => ({
  type: CIRCLE_FETCH_REQUEST,
  id,
});

export const fetchCircleSuccess = circle => ({
  type: CIRCLE_FETCH_SUCCESS,
  circle,
});

export const fetchCircleFail = (id, error) => ({
  type: CIRCLE_FETCH_FAIL,
  id,
  error,
});

export const deleteCircle = id => (dispatch) => {
  dispatch(deleteCircleRequest(id));

  api().delete(`/api/v1/circles/${id}`)
    .then(() => dispatch(deleteCircleSuccess(id)))
    .catch(err => dispatch(deleteCircleFail(id, err)));
};

export const deleteCircleRequest = id => ({
  type: CIRCLE_DELETE_REQUEST,
  id,
});

export const deleteCircleSuccess = id => ({
  type: CIRCLE_DELETE_SUCCESS,
  id,
});

export const deleteCircleFail = (id, error) => ({
  type: CIRCLE_DELETE_FAIL,
  id,
  error,
});
