import { AxiosError } from 'axios';
import { Record, fromJS } from 'immutable';

import api, { getLinks } from '../../api';
import {
  SCHEDULED_STATUSES_FETCH_SUCCESS,
  deleteScheduledStatus,
  fetchScheduledStatuses,
  setComposeToScheduledStatus,
  updateScheduledStatus,
} from '../scheduled_statuses';

vi.mock('../../api', () => ({ default: vi.fn(), getLinks: vi.fn() }));
vi.mock('../compose', () => ({ ensureComposeIsVisible: vi.fn() }));

const apiGet = vi.fn();
const apiPut = vi.fn();
const apiDelete = vi.fn();

const serverError = () => new AxiosError('Request failed', 'ERR_BAD_RESPONSE', undefined, undefined, {
  status: 500,
  statusText: 'Internal Server Error',
  headers: {},
  data: { error: 'Scheduled post failed' },
});

const alertsFrom = dispatch => dispatch.mock.calls.map(([action]) => action).filter(action => action.type === 'alerts/show');

beforeEach(() => {
  vi.clearAllMocks();
  apiGet.mockReset();
  apiPut.mockReset();
  apiDelete.mockReset();
  vi.mocked(api).mockReturnValue({ get: apiGet, put: apiPut, delete: apiDelete });
  vi.mocked(getLinks).mockImplementation(result => ({ refs: result.next ? [{ rel: 'next', uri: result.next }] : [] }));
});

test('fetchScheduledStatuses follows next links until the last page', async () => {
  apiGet
    .mockResolvedValueOnce({ data: [{ id: '3' }, { id: '2' }], next: '/api/v1/scheduled_statuses?limit=40&max_id=2' })
    .mockResolvedValueOnce({ data: [{ id: '1' }], next: null });
  const dispatch = vi.fn();

  await fetchScheduledStatuses()(dispatch);

  expect(apiGet).toHaveBeenNthCalledWith(1, '/api/v1/scheduled_statuses?limit=40');
  expect(apiGet).toHaveBeenNthCalledWith(2, '/api/v1/scheduled_statuses?limit=40&max_id=2');
  const success = dispatch.mock.calls.map(([action]) => action).find(action => action.type === SCHEDULED_STATUSES_FETCH_SUCCESS);
  expect(success.statuses.map(status => status.get('id'))).toEqual(['3', '2', '1']);
});

test('fetchScheduledStatuses stops after the scheduled post limit worth of pages', async () => {
  apiGet.mockImplementation(() => Promise.resolve({ data: [{ id: '1' }], next: '/api/v1/scheduled_statuses?max_id=1' }));

  await fetchScheduledStatuses()(vi.fn());

  expect(apiGet).toHaveBeenCalledTimes(8);
});

test('fetchScheduledStatuses shows an alert when loading fails', async () => {
  apiGet.mockRejectedValue(serverError());
  const dispatch = vi.fn();

  await fetchScheduledStatuses()(dispatch);

  expect(alertsFrom(dispatch)).toEqual([expect.objectContaining({ payload: expect.objectContaining({ message: 'Scheduled post failed' }) })]);
});

test('updateScheduledStatus shows an alert when the change fails', async () => {
  apiPut.mockRejectedValue(serverError());
  const dispatch = vi.fn();

  await updateScheduledStatus('1', '2031-01-01T00:00:00.000Z')(dispatch);
  await vi.waitFor(() => expect(alertsFrom(dispatch)).toHaveLength(1));
  expect(dispatch).toHaveBeenCalledWith({ type: 'SCHEDULED_STATUS_UPDATE_FAIL', id: '1' });
});

test('deleteScheduledStatus shows an alert when the deletion fails', async () => {
  apiDelete.mockRejectedValue(serverError());
  const dispatch = vi.fn();

  await deleteScheduledStatus('1')(dispatch);
  await vi.waitFor(() => expect(alertsFrom(dispatch)).toHaveLength(1));
  expect(dispatch).toHaveBeenCalledWith({ type: 'SCHEDULED_STATUS_DELETE_FAIL', id: '1' });
});

test('setComposeToScheduledStatus passes the server poll option limit', () => {
  const state = Record({ server: undefined })({
    server: fromJS({ server: { item: { configuration: { polls: { max_options: 10 } } } } }),
  });
  const dispatch = vi.fn();

  setComposeToScheduledStatus(fromJS({ id: '1' }))(dispatch, () => state);

  expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({ type: 'COMPOSE_SET_SCHEDULED', maxOptions: 10 }));
});
