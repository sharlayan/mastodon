import api from '../api';

export const ANTENNAS_FETCH_REQUEST = 'ANTENNAS_FETCH_REQUEST';
export const ANTENNAS_FETCH_SUCCESS = 'ANTENNAS_FETCH_SUCCESS';
export const ANTENNAS_FETCH_FAIL    = 'ANTENNAS_FETCH_FAIL';

export const ANTENNA_FETCH_REQUEST = 'ANTENNA_FETCH_REQUEST';
export const ANTENNA_FETCH_SUCCESS = 'ANTENNA_FETCH_SUCCESS';
export const ANTENNA_FETCH_FAIL    = 'ANTENNA_FETCH_FAIL';

export const ANTENNA_CREATE_SUCCESS = 'ANTENNA_CREATE_SUCCESS';
export const ANTENNA_UPDATE_SUCCESS = 'ANTENNA_UPDATE_SUCCESS';

export const ANTENNA_DELETE_REQUEST = 'ANTENNA_DELETE_REQUEST';
export const ANTENNA_DELETE_SUCCESS = 'ANTENNA_DELETE_SUCCESS';
export const ANTENNA_DELETE_FAIL    = 'ANTENNA_DELETE_FAIL';

export const fetchAntennas = () => (dispatch) => {
  dispatch({ type: ANTENNAS_FETCH_REQUEST });

  return api().get('/api/v1/antennas')
    .then(({ data }) => dispatch({ type: ANTENNAS_FETCH_SUCCESS, antennas: data }))
    .catch(err => dispatch({ type: ANTENNAS_FETCH_FAIL, error: err }));
};

export const fetchAntenna = id => (dispatch, getState) => {
  if (getState().getIn(['antennas', id])) {
    return;
  }

  dispatch({ type: ANTENNA_FETCH_REQUEST, id });

  api().get(`/api/v1/antennas/${id}`)
    .then(({ data }) => dispatch({ type: ANTENNA_FETCH_SUCCESS, antenna: data }))
    .catch(err => dispatch({ type: ANTENNA_FETCH_FAIL, id, error: err }));
};

export const createAntenna = params => (dispatch) =>
  api().post('/api/v1/antennas', params)
    .then(({ data }) => {
      dispatch({ type: ANTENNA_CREATE_SUCCESS, antenna: data });
      return data;
    });

export const updateAntenna = (id, params) => (dispatch) =>
  api().put(`/api/v1/antennas/${id}`, params)
    .then(({ data }) => {
      dispatch({ type: ANTENNA_UPDATE_SUCCESS, antenna: data });
      return data;
    });

export const deleteAntenna = id => (dispatch) => {
  dispatch({ type: ANTENNA_DELETE_REQUEST, id });

  api().delete(`/api/v1/antennas/${id}`)
    .then(() => dispatch({ type: ANTENNA_DELETE_SUCCESS, id }))
    .catch(err => dispatch({ type: ANTENNA_DELETE_FAIL, id, error: err }));
};

const refreshAfter = (id, request) => (dispatch) =>
  request.then(() => api().get(`/api/v1/antennas/${id}`))
    .then(({ data }) => dispatch({ type: ANTENNA_FETCH_SUCCESS, antenna: data }));

export const saveAntenna = (id, { main, add, remove }) => (dispatch) => {
  const chipCall = (kind, values, method) => {
    if (!values || values.length === 0) return null;
    const path = `/api/v1/antennas/${id}/${kind}`;
    if (kind === 'accounts' || kind === 'exclude_accounts') {
      return method === 'post'
        ? api().post(path, { account_ids: values })
        : api().delete(path, { data: { account_ids: values } });
    }
    const key = (kind === 'tags' || kind === 'exclude_tags') ? 'tags' : 'domains';
    return method === 'post'
      ? api().post(path, { [key]: values })
      : api().delete(path, { data: { [key]: values } });
  };

  return api().put(`/api/v1/antennas/${id}`, main)
    .then(() => Promise.all([
      chipCall('domains', add.domains, 'post'),
      chipCall('domains', remove.domains, 'delete'),
      chipCall('exclude_domains', add.exclude_domains, 'post'),
      chipCall('exclude_domains', remove.exclude_domains, 'delete'),
      chipCall('tags', add.tags, 'post'),
      chipCall('tags', remove.tags, 'delete'),
      chipCall('exclude_tags', add.exclude_tags, 'post'),
      chipCall('exclude_tags', remove.exclude_tags, 'delete'),
      chipCall('accounts', add.accounts, 'post'),
      chipCall('accounts', remove.accounts, 'delete'),
      chipCall('exclude_accounts', add.exclude_accounts, 'post'),
      chipCall('exclude_accounts', remove.exclude_accounts, 'delete'),
    ].filter(Boolean)))
    .then(() => api().get(`/api/v1/antennas/${id}`))
    .then(({ data }) => dispatch({ type: ANTENNA_UPDATE_SUCCESS, antenna: data }));
};

export const addAntennaDomains = (id, domains, exclude = false) => (dispatch) =>
  dispatch(refreshAfter(id, api().post(`/api/v1/antennas/${id}/${exclude ? 'exclude_domains' : 'domains'}`, { domains })));

export const removeAntennaDomains = (id, domains, exclude = false) => (dispatch) =>
  dispatch(refreshAfter(id, api().delete(`/api/v1/antennas/${id}/${exclude ? 'exclude_domains' : 'domains'}`, { data: { domains } })));

export const addAntennaTags = (id, tags, exclude = false) => (dispatch) =>
  dispatch(refreshAfter(id, api().post(`/api/v1/antennas/${id}/${exclude ? 'exclude_tags' : 'tags'}`, { tags })));

export const removeAntennaTags = (id, tags, exclude = false) => (dispatch) =>
  dispatch(refreshAfter(id, api().delete(`/api/v1/antennas/${id}/${exclude ? 'exclude_tags' : 'tags'}`, { data: { tags } })));

export const addAntennaAccount = (id, accountId, exclude = false) => (dispatch) =>
  dispatch(refreshAfter(id, api().post(`/api/v1/antennas/${id}/${exclude ? 'exclude_accounts' : 'accounts'}`, { account_ids: [accountId] })));

export const removeAntennaAccount = (id, accountId, exclude = false) => (dispatch) =>
  dispatch(refreshAfter(id, api().delete(`/api/v1/antennas/${id}/${exclude ? 'exclude_accounts' : 'accounts'}`, { data: { account_ids: [accountId] } })));
