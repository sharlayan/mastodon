import { IntlProvider } from 'react-intl';

import { Router } from 'react-router-dom';

import { fromJS, Map as ImmutableMap } from 'immutable';

import { fireEvent, render, screen } from '@testing-library/react';
import { createMemoryHistory } from 'history';

import { EmbeddedStatus } from '../embedded_status';

interface FakeState {
  statuses?: unknown;
  accounts?: unknown;
}

const { dispatch, navigateToStatusOrConversation, state } = vi.hoisted(() => {
  const fakeState: FakeState = {};
  return {
    dispatch: vi.fn(),
    navigateToStatusOrConversation: vi.fn((id: string) => ({
      type: 'conversation',
      id,
    })),
    state: fakeState,
  };
});

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => dispatch,
  useAppSelector: (select: (value: unknown) => unknown) => select(state),
}));
vi.mock('flavours/glitch/actions/statuses', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  navigateToStatusOrConversation,
  toggleStatusSpoilers: vi.fn(),
}));
vi.mock('flavours/glitch/components/avatar', () => ({ Avatar: () => null }));
vi.mock('flavours/glitch/components/display_name', () => ({
  DisplayName: () => null,
}));
vi.mock('@/flavours/glitch/components/status/legacy/content_warning', () => ({
  ContentWarning: () => null,
}));
vi.mock('../embedded_status_content', () => ({
  EmbeddedStatusContent: () => <p>Status text</p>,
}));

const mount = (visibility: string) => {
  state.statuses = fromJS({
    '1': {
      id: '1',
      account: 'a',
      visibility,
      spoiler_text: '',
      hidden: false,
      media_attachments: [],
      poll: null,
    },
  });
  state.accounts = ImmutableMap({ a: { id: 'a', acct: 'alice' } });
  const history = createMemoryHistory({ initialEntries: ['/notifications'] });
  render(
    <IntlProvider locale='en'>
      <Router history={history}>
        <EmbeddedStatus statusId='1' />
      </Router>
    </IntlProvider>,
  );
  const target = screen.getByText('Status text');
  fireEvent.mouseDown(target, { clientX: 1, clientY: 1, button: 0 });
  fireEvent.mouseUp(target, { clientX: 1, clientY: 1, button: 0 });
  return history;
};

describe('EmbeddedStatus in a notification', () => {
  beforeEach(() => {
    dispatch.mockClear();
    navigateToStatusOrConversation.mockClear();
  });

  it('opens a private mention in its conversation', () => {
    const history = mount('direct');

    expect(navigateToStatusOrConversation).toHaveBeenCalledWith('1');
    expect(dispatch).toHaveBeenCalledWith({ type: 'conversation', id: '1' });
    expect(history.location.pathname).toBe('/notifications');
  });

  it('opens any other post on its own page', () => {
    const history = mount('public');

    expect(navigateToStatusOrConversation).not.toHaveBeenCalled();
    expect(history.location.pathname).toBe('/@alice/1');
  });
});
