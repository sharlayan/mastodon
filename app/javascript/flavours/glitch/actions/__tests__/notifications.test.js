import { fromJS } from 'immutable';

import { updateNotifications } from '../notifications';

vi.mock('../accounts', () => ({ fetchFollowRequests: vi.fn() }));
vi.mock('../importer', () => ({
  importFetchedAccount: account => ({ type: 'TEST_IMPORT_ACCOUNT', account }),
}));
vi.mock('../markers', () => ({
  submitMarkers: () => ({ type: 'TEST_SUBMIT_MARKERS' }),
}));
vi.mock('../push_notifications', () => ({ register: vi.fn() }));

const notification = {
  id: '1',
  type: 'mention',
  account: {
    id: '2',
    display_name: 'Alice',
    username: 'alice',
    avatar: '/avatar.png',
  },
  status: {
    visibility: 'direct',
    spoiler_text: '',
    content: '<p>Hello &amp; welcome</p>',
  },
};

const messages = { 'notification.mention': '{name} mentioned you' };
const state = fromJS({ settings: {} });

describe('updateNotifications', () => {
  let createNotification;
  let popup;
  let dispatch;

  beforeEach(() => {
    popup = { addEventListener: vi.fn(), close: vi.fn() };
    createNotification = vi.fn(function () { return popup; });
    createNotification.permission = 'granted';
    vi.stubGlobal('Notification', createNotification);
    dispatch = vi.fn();
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  const receiveNotification = (intlMessages = messages) => {
    updateNotifications(notification, intlMessages, 'en')(dispatch, () => state);
  };

  const expectReduxNotification = () => {
    expect(dispatch).toHaveBeenCalledWith({
      type: 'notifications/update',
      payload: { notification },
      meta: { sound: 'boop' },
    });
  };

  it('keeps the DM notification without displaying a popup when permission is denied or default', () => {
    for (const permission of ['denied', 'default']) {
      dispatch.mockClear();
      createNotification.permission = permission;

      receiveNotification();

      expect(createNotification).not.toHaveBeenCalled();
      expectReduxNotification();
    }
  });

  it('keeps the DM notification when browser notifications are unsupported', () => {
    vi.stubGlobal('Notification', undefined);

    receiveNotification();

    expectReduxNotification();
  });

  it('displays a popup when permission is granted and focuses the app when clicked', () => {
    const focus = vi.spyOn(window, 'focus').mockImplementation(() => {});

    receiveNotification();

    expectReduxNotification();
    expect(createNotification).toHaveBeenCalledWith('Alice mentioned you', {
      body: 'Hello & welcome',
      icon: '/avatar.png',
      tag: '1',
    });
    expect(popup.addEventListener).toHaveBeenCalledWith('click', expect.any(Function));

    popup.addEventListener.mock.calls[0][1]();

    expect(focus).toHaveBeenCalledOnce();
    expect(popup.close).toHaveBeenCalledOnce();
  });

  it('keeps DM processing running when the browser notification constructor throws TypeError or SecurityError', () => {
    for (const error of [
      new TypeError('Illegal constructor'),
      new DOMException('Notifications are blocked', 'SecurityError'),
    ]) {
      dispatch.mockClear();
      console.error.mockClear();
      createNotification.mockImplementation(function () { throw error; });

      expect(receiveNotification).not.toThrow();

      expectReduxNotification();
      expect(console.error).toHaveBeenCalled();
    }
  });

  it('keeps DM processing running when the popup message cannot be formatted', () => {
    expect(() => receiveNotification({ 'notification.mention': '{name' })).not.toThrow();

    expectReduxNotification();
    expect(console.error).toHaveBeenCalled();
  });

  it('keeps DM processing running when popup event binding fails', () => {
    popup.addEventListener.mockImplementation(() => { throw new TypeError('Event binding failed'); });

    expect(receiveNotification).not.toThrow();

    expectReduxNotification();
    expect(console.error).toHaveBeenCalled();
  });
});
