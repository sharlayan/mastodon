import api, { getLinks } from 'flavours/glitch/api';

import { STATUS_DRAFTS_FETCH_SUCCESS, fetchStatusDrafts } from '../status_drafts';

vi.mock('flavours/glitch/api', () => ({ default: vi.fn(), getLinks: vi.fn() }));

const apiGet = vi.fn();

beforeEach(() => {
  vi.clearAllMocks();
  apiGet.mockReset();
  vi.mocked(api).mockReturnValue({ get: apiGet });
  vi.mocked(getLinks).mockImplementation(result => ({ refs: result.next ? [{ rel: 'next', uri: result.next }] : [] }));
});

test('fetchStatusDrafts follows next links until the last page', async () => {
  apiGet
    .mockResolvedValueOnce({ data: [{ id: '3' }, { id: '2' }], next: '/api/v1/status_drafts?max_id=2' })
    .mockResolvedValueOnce({ data: [{ id: '1' }], next: null });
  const dispatch = vi.fn();

  await fetchStatusDrafts()(dispatch);

  expect(apiGet).toHaveBeenNthCalledWith(2, '/api/v1/status_drafts?max_id=2');
  const success = dispatch.mock.calls.map(([action]) => action).find(action => action.type === STATUS_DRAFTS_FETCH_SUCCESS);
  expect(success.drafts.map(draft => draft.get('id')).toArray()).toEqual(['3', '2', '1']);
});

test('fetchStatusDrafts stops after the draft limit worth of pages', async () => {
  apiGet.mockImplementation(() => Promise.resolve({ data: [{ id: '1' }], next: '/api/v1/status_drafts?max_id=1' }));

  await fetchStatusDrafts()(vi.fn());

  expect(apiGet).toHaveBeenCalledTimes(5);
});
