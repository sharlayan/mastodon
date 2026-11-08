import api, { getLinks } from '../../api';
import { SCHEDULED_STATUSES_FETCH_SUCCESS, fetchScheduledStatuses } from '../scheduled_statuses';

vi.mock('../../api', () => ({ default: vi.fn(), getLinks: vi.fn() }));
vi.mock('../compose', () => ({ ensureComposeIsVisible: vi.fn() }));

const apiGet = vi.fn();

beforeEach(() => {
  vi.clearAllMocks();
  apiGet.mockReset();
  vi.mocked(api).mockReturnValue({ get: apiGet });
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
