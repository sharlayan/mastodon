import api, { getLinks } from 'flavours/glitch/api';

import { fromJS } from 'immutable';

import {
  STATUS_DRAFTS_FETCH_SUCCESS,
  STATUS_DRAFT_DELETE_SUCCESS,
  STATUS_DRAFT_SAVE_REQUEST,
  discardPendingStatusDraftSave,
  fetchStatusDrafts,
  getPendingStatusDraftSave,
  saveStatusDraft,
} from '../status_drafts';

vi.mock('flavours/glitch/api', () => ({ default: vi.fn(), getLinks: vi.fn() }));

const apiGet = vi.fn();
const apiPost = vi.fn();
const apiPut = vi.fn();
const apiDelete = vi.fn();

const composeState = (compose) => fromJS({
  compose: {
    text: 'Draft text',
    spoiler: false,
    spoiler_text: '',
    media_attachments: [],
    clip_ids: [],
    poll: null,
    advanced_options: { do_not_federate: false },
    draft_id: null,
    draft_save_request: null,
    ...compose,
  },
});

beforeEach(() => {
  vi.clearAllMocks();
  apiGet.mockReset();
  apiPost.mockReset();
  apiPut.mockReset();
  apiDelete.mockReset();
  vi.mocked(api).mockReturnValue({ get: apiGet, post: apiPost, put: apiPut, delete: apiDelete });
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

test('saveStatusDraft does not start a second save while one is in flight', async () => {
  const dispatch = vi.fn();

  await saveStatusDraft()(dispatch, () => composeState({ draft_save_request: 'save-1' }));

  expect(apiPost).not.toHaveBeenCalled();
  expect(dispatch).not.toHaveBeenCalled();
});

test('saveStatusDraft tags the request and its result with the same request id', async () => {
  apiPost.mockResolvedValue({ data: { id: '9' } });
  const dispatch = vi.fn();

  await saveStatusDraft()(dispatch, () => composeState());

  const [request, success] = dispatch.mock.calls.map(([action]) => action);
  expect(request.type).toBe(STATUS_DRAFT_SAVE_REQUEST);
  expect(success.requestId).toBe(request.requestId);
  expect(apiPost).toHaveBeenCalledOnce();
});

const deferred = () => {
  let resolveDeferred;
  const promise = new Promise((resolve) => { resolveDeferred = resolve; });
  return { promise, resolve: resolveDeferred };
};

const startSave = (compose) => {
  const dispatch = vi.fn(action => (typeof action === 'function' ? action(dispatch) : action));
  const done = saveStatusDraft()(dispatch, () => composeState(compose));
  const request = dispatch.mock.calls[0][0];
  return { dispatch, done, pending: getPendingStatusDraftSave(request.requestId) };
};

test('publishing while the first draft save is in flight deletes the draft that save creates', async () => {
  const response = deferred();
  apiPost.mockReturnValue(response.promise);
  apiDelete.mockResolvedValue({});
  const { dispatch, done, pending } = startSave();

  const discarded = discardPendingStatusDraftSave(pending, null)(dispatch);
  response.resolve({ data: { id: '9' } });
  await done;
  await discarded;

  expect(apiDelete).toHaveBeenCalledWith('/api/v1/status_drafts/9');
  expect(dispatch.mock.calls.map(([action]) => action)).toContainEqual({ type: STATUS_DRAFT_DELETE_SUCCESS, id: '9' });
  expect(dispatch.mock.calls.some(([action]) => action?.type === 'alerts/show')).toBe(false);
  expect(getPendingStatusDraftSave(dispatch.mock.calls[0][0].requestId)).toBeNull();
});

test('publishing while an existing draft is being updated does not delete it a second time', async () => {
  const response = deferred();
  apiPut.mockReturnValue(response.promise);
  const { dispatch, done, pending } = startSave({ draft_id: '5' });

  const discarded = discardPendingStatusDraftSave(pending, '5')(dispatch);
  response.resolve({ data: { id: '5' } });
  await done;
  await discarded;

  expect(apiDelete).not.toHaveBeenCalled();
});
