import {
  createAntennaStreamConnector,
  getLinkedNotificationAlert,
  handleSharlayanStreamingEvent,
  updateLinkedNotificationLastSeen,
} from '../streaming';

const linked = {
  linked_account_id: '2',
  linked_account_acct: 'linked@example.com',
  notification: {
    id: '11',
    type: 'mention',
    account: { display_name: 'Sender', username: 'sender' },
  },
};

const createStorage = (values = {}) => ({
  getItem: vi.fn((key) => values[key] ?? null),
  setItem: vi.fn((key, value) => {
    values[key] = value;
  }),
});

describe('compose streaming extensions', () => {
  it('handles reaction events without claiming upstream events', () => {
    const dispatch = vi.fn();
    const updateReaction = vi.fn((payload, options) => ({ payload, options }));

    expect(handleSharlayanStreamingEvent({
      bogusQuotePolicy: true,
      data: { event: 'status.reaction', payload: '{"id":"1"}' },
      dispatch,
      getState: vi.fn(),
      messages: {},
      storage: createStorage(),
      updateReaction,
    })).toBe(true);
    expect(dispatch).toHaveBeenCalledWith({ payload: { id: '1' }, options: { bogusQuotePolicy: true } });
    expect(handleSharlayanStreamingEvent({
      data: { event: 'update', payload: '{}' },
      dispatch,
      getState: vi.fn(),
      messages: {},
      storage: createStorage(),
      updateReaction,
    })).toBe(false);
  });

  it('honors linked-account toast preferences and the active account guard', () => {
    const storage = createStorage({
      linked_notif_prefs_1: JSON.stringify({ 2: { inApp: true } }),
    });
    const messages = { 'notification.mention': '{name} mentioned you' };

    expect(getLinkedNotificationAlert({ activeAccountId: '1', linked, messages, rootAccountId: '1', storage })).toEqual({
      title: '@linked@example.com',
      message: 'Sender mentioned you',
    });
    expect(getLinkedNotificationAlert({ activeAccountId: '2', linked, messages, rootAccountId: '1', storage })).toBeNull();
  });

  it('only advances the linked-account last-seen id', () => {
    const values = { linked_notif_last_id_1_2: '10' };
    const storage = createStorage(values);

    updateLinkedNotificationLastSeen({ activeAccountId: '1', linked, storage });
    expect(values.linked_notif_last_id_1_2).toBe('11');

    updateLinkedNotificationLastSeen({ activeAccountId: '1', linked: { ...linked, notification: { ...linked.notification, id: '9' } }, storage });
    expect(values.linked_notif_last_id_1_2).toBe('11');
  });

  it('preserves the antenna timeline id, channel, params, and gap fill', () => {
    const connectTimeline = vi.fn((_timeline, _channel, _params, options) => options);
    const fillGaps = vi.fn((id) => ({ id }));
    const connectAntennaStream = createAntennaStreamConnector({ connectTimeline, fillGaps });
    const options = connectAntennaStream('7');

    expect(connectTimeline).toHaveBeenCalledWith('antenna:7', 'antenna', { antenna: '7' }, expect.any(Object));
    expect(options.fillGaps()).toEqual({ id: '7' });
  });
});
