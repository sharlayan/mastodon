import { fromJS } from 'immutable';

import api from '../../api';

import {
  DIRECT_COMPOSE_SUBMIT_FAIL,
  DIRECT_COMPOSE_SUBMIT_SUCCESS,
  DIRECT_COMPOSE_UPLOAD_FAIL,
  submitDirectMessage,
  uploadDirectMedia,
} from '../direct_compose';
import { dismissNotificationsForStatuses } from '../notification_groups';

vi.mock('../../api', () => ({ default: vi.fn() }));
vi.mock('../../initial_state', () => ({ me: 'self' }));
vi.mock('../alerts', () => ({
  showAlert: vi.fn(() => ({ type: 'TEST_ALERT' })),
  showAlertForError: vi.fn(error => ({ type: 'TEST_ALERT_FOR_ERROR', error })),
}));
vi.mock('../importer', () => ({ importFetchedStatus: vi.fn(() => ({ type: 'TEST_IMPORT' })) }));
vi.mock('../timelines', () => ({ updateTimeline: vi.fn(() => ({ type: 'TEST_TIMELINE_UPDATE' })) }));
vi.mock('../notification_groups', () => ({
  dismissNotificationsForStatuses: vi.fn(statusIds => ({ type: 'TEST_DISMISS', statusIds })),
}));

const apiPost = vi.fn();
const reply = { id: 'sent', visibility: 'direct', in_reply_to_id: 'received' };
let state;

const sendReply = (dispatch = vi.fn()) => ({
  dispatch,
  result: submitDirectMessage('conversation', {
    inReplyToId: 'received',
    recipientIds: ['sender'],
  })(dispatch, () => state),
});

describe('direct message notification retention', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    apiPost.mockReset();
    vi.mocked(api).mockReturnValue({ post: apiPost });
    state = fromJS({
      accounts: { sender: { acct: 'sender' } },
      direct_compose: { conversation: { text: 'Reply' } },
      timelines: {
        'conversation:conversation': { items: ['received', 'own', null, 'public'] },
        'conversation:other': { items: ['other'] },
      },
      statuses: {
        received: { visibility: 'direct', account: 'sender' },
        own: { visibility: 'direct', account: 'self' },
        public: { visibility: 'public', account: 'sender' },
        other: { visibility: 'direct', account: 'sender' },
      },
    });
  });

  it('does not send while an attachment is still uploading', async () => {
    state = state.setIn(['direct_compose', 'conversation', 'is_uploading'], true);

    const { dispatch, result } = sendReply();
    await result;

    expect(apiPost).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('retains notifications until the reply request succeeds', async () => {
    let complete;
    apiPost.mockReturnValue(new Promise(resolve => { complete = resolve; }));

    const { dispatch, result } = sendReply();

    expect(dismissNotificationsForStatuses).not.toHaveBeenCalled();

    complete({ data: reply });
    await result;

    expect(dispatch).toHaveBeenCalledWith({ type: DIRECT_COMPOSE_SUBMIT_SUCCESS, conversationId: 'conversation' });
    expect(dismissNotificationsForStatuses).toHaveBeenCalledWith(['received', 'own']);
  });

  it('retains notifications when sending fails', async () => {
    const error = new Error('Request failed');
    apiPost.mockRejectedValue(error);

    const { dispatch, result } = sendReply();
    await result;

    expect(dispatch).toHaveBeenCalledWith({ type: DIRECT_COMPOSE_SUBMIT_FAIL, conversationId: 'conversation', error });
    expect(dismissNotificationsForStatuses).not.toHaveBeenCalled();
  });

  it('does not dismiss messages received while the reply is being sent', async () => {
    let complete;
    apiPost.mockReturnValue(new Promise(resolve => { complete = resolve; }));
    const { result } = sendReply();

    state = state
      .setIn(['statuses', 'new'], fromJS({ visibility: 'direct', account: 'sender' }))
      .updateIn(['timelines', 'conversation:conversation', 'items'], items => items.unshift('new'));
    complete({ data: reply });
    await result;

    expect(dismissNotificationsForStatuses).toHaveBeenCalledWith(['received', 'own']);
  });

  it.each([
    ['empty', { text: '' }],
    ['already submitting', { text: 'Reply', is_submitting: true }],
  ])('retains notifications for an %s composer', async (_label, composer) => {
    state = state.setIn(['direct_compose', 'conversation'], fromJS(composer));

    const { result } = sendReply();
    await result;

    expect(apiPost).not.toHaveBeenCalled();
    expect(dismissNotificationsForStatuses).not.toHaveBeenCalled();
  });
});

describe('direct message uploads', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    apiPost.mockReset();
    vi.mocked(api).mockReturnValue({ post: apiPost });
    apiPost.mockReturnValue(new Promise(() => {}));
  });

  it('does not start another upload while one is in progress', () => {
    state = fromJS({ direct_compose: { conversation: { is_uploading: true, media: [] } } });
    const dispatch = vi.fn();

    uploadDirectMedia('conversation', [new File(['a'], 'a.png')])(dispatch, () => state);

    expect(apiPost).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('starts an upload when none is in progress', () => {
    state = fromJS({ direct_compose: { conversation: { is_uploading: false, media: [] } } });
    const dispatch = vi.fn();

    uploadDirectMedia('conversation', [new File(['a'], 'a.png')])(dispatch, () => state);

    expect(apiPost).toHaveBeenCalledTimes(1);
  });

  it('shows an alert when the upload fails', async () => {
    state = fromJS({ direct_compose: { conversation: { is_uploading: false, media: [] } } });
    const error = new Error('Request failed');
    apiPost.mockRejectedValue(error);
    const dispatch = vi.fn();

    uploadDirectMedia('conversation', [new File(['a'], 'a.png')])(dispatch, () => state);

    await vi.waitFor(() => expect(dispatch).toHaveBeenCalledWith({ type: DIRECT_COMPOSE_UPLOAD_FAIL, conversationId: 'conversation', error }));
    expect(dispatch).toHaveBeenCalledWith({ type: 'TEST_ALERT_FOR_ERROR', error });
  });
});
