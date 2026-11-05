import PropTypes from 'prop-types';

import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router-dom';

import { fromJS } from 'immutable';
import { useDispatch, useSelector } from 'react-redux';

import { cleanup, render } from '@testing-library/react';

import { dismissNotificationsForStatuses } from 'flavours/glitch/actions/notification_groups';

import ConversationThread from '../conversation';

vi.mock('react-redux', async importOriginal => ({
  ...(await importOriginal()),
  useDispatch: Object.assign(vi.fn(), { withTypes: () => vi.fn() }),
  useSelector: Object.assign(vi.fn(), { withTypes: () => vi.fn() }),
}));
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));
vi.mock('flavours/glitch/initial_state', () => ({ me: 'self' }));
vi.mock('flavours/glitch/actions/columns', () => ({ addColumn: vi.fn(), removeColumn: vi.fn(), moveColumn: vi.fn() }));
vi.mock('flavours/glitch/actions/conversations', () => ({
  markConversationRead: vi.fn(() => ({ type: 'TEST_READ' })),
  expandConversationStatuses: vi.fn(() => ({ type: 'TEST_EXPAND' })),
}));
vi.mock('flavours/glitch/actions/modal', () => ({ openModal: vi.fn() }));
vi.mock('flavours/glitch/actions/notification_groups', () => ({
  dismissNotificationsForStatuses: vi.fn(() => ({ type: 'TEST_DISMISS' })),
}));
vi.mock('flavours/glitch/actions/streaming', () => ({ connectDirectStream: vi.fn() }));
vi.mock('flavours/glitch/actions/timelines', () => ({ clearTimeline: vi.fn(), TIMELINE_NON_STATUS_MARKERS: [null, 'inline-follow-suggestions', 'pinned-view-all'] }));
vi.mock('flavours/glitch/components/column', () => {
  const Column = ({ children }) => <div>{children}</div>;
  Column.propTypes = { children: PropTypes.node };
  return { Column };
});
vi.mock('flavours/glitch/components/column/header', () => ({ ColumnHeader: () => null }));
vi.mock('flavours/glitch/components/circular_progress', () => ({ CircularProgress: () => null }));
vi.mock('flavours/glitch/components/display_name', () => ({ DisplayName: () => null }));
vi.mock('flavours/glitch/components/icon_button', () => ({ IconButton: () => null }));
vi.mock('../components/chat_message', () => ({ ChatMessage: () => null }));
vi.mock('../components/direct_composer', () => ({ DirectComposer: () => null }));

let state;

const conversationView = () => (
  <MemoryRouter>
    <IntlProvider locale='en'>
      <ConversationThread params={{ id: 'conversation' }} />
    </IntlProvider>
  </MemoryRouter>
);

describe('opening a DM conversation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(useDispatch).mockReturnValue(vi.fn(() => vi.fn()));
    vi.mocked(useSelector).mockImplementation(selector => selector(state));
    state = fromJS({
      conversations: { items: [] },
      accounts: {},
      statuses: { received: { account: 'sender', visibility: 'direct' } },
      timelines: { 'conversation:conversation': { items: ['received'] } },
    });
    state.notificationGroups = { groups: [{ type: 'mention', statusId: 'received' }] };
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it.each(['visible', 'hidden'])('retains existing and incoming notifications in a %s tab', visibilityState => {
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue(visibilityState);
    const { rerender } = render(conversationView());

    expect(dismissNotificationsForStatuses).not.toHaveBeenCalled();

    state = state
      .setIn(['statuses', 'new'], fromJS({ account: 'sender', visibility: 'direct' }))
      .updateIn(['timelines', 'conversation:conversation', 'items'], items => items.unshift('new'));
    state.notificationGroups = { groups: [{ type: 'mention', statusId: 'new' }] };
    rerender(conversationView());

    expect(dismissNotificationsForStatuses).not.toHaveBeenCalled();
  });
});
