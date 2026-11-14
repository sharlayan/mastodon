import { fromJS } from 'immutable';

import { render } from '@testing-library/react';

import { NotificationWithStatus } from '../notification_with_status';

interface FakeState {
  statuses?: unknown;
  accounts?: unknown;
  local_settings?: unknown;
}

const {
  dispatch,
  navigateToStatus,
  navigateToStatusOrConversation,
  opened,
  state,
} = vi.hoisted(() => {
  const fakeState: FakeState = {};
  return {
    dispatch: vi.fn(),
    navigateToStatus: vi.fn((id: string) => ({ type: 'status', id })),
    navigateToStatusOrConversation: vi.fn((id: string) => ({
      type: 'conversation',
      id,
    })),
    opened: { current: undefined as (() => void) | undefined },
    state: fakeState,
  };
});

vi.mock('flavours/glitch-classic/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => dispatch,
  useAppSelector: (select: (value: unknown) => unknown) => select(state),
}));
vi.mock('flavours/glitch-classic/actions/statuses', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  navigateToStatus,
  navigateToStatusOrConversation,
}));
vi.mock(
  'flavours/glitch-classic/selectors/filters',
  async (importOriginal) => ({
    ...(await importOriginal<object>()),
    getStatusHidden: () => false,
  }),
);
vi.mock('@/flavours/glitch-classic/components/display_name', () => ({
  LinkedDisplayName: () => null,
}));
vi.mock('flavours/glitch-classic/components/hotkeys', () => ({
  Hotkeys: ({ children }: { children: React.ReactNode }) => children,
}));
vi.mock('flavours/glitch-classic/components/icon', () => ({
  Icon: () => null,
}));
vi.mock('flavours/glitch-classic/components/status', () => ({
  Status: ({ onOpen }: { onOpen?: () => void }) => {
    opened.current = onOpen;
    return null;
  },
}));

const NoIcon = () => null;
const label = () => <span>Liked</span>;

const mount = (visibility: string, openAsConversation?: boolean) => {
  state.statuses = fromJS({ '1': { id: '1', visibility } });
  state.local_settings = fromJS({ collapsed: { auto: {} } });
  state.accounts = fromJS({});
  opened.current = undefined;
  render(
    <NotificationWithStatus
      type='favourite'
      icon={NoIcon}
      iconId='star'
      accountIds={['a']}
      statusId='1'
      count={1}
      labelRenderer={label}
      unread={false}
      openAsConversation={openAsConversation}
    />,
  );
};

describe('NotificationWithStatus', () => {
  beforeEach(() => {
    dispatch.mockClear();
  });

  it('opens a liked private mention in its conversation', () => {
    mount('direct');

    opened.current?.();

    expect(dispatch).toHaveBeenCalledWith({ type: 'conversation', id: '1' });
  });

  it('leaves other posts to open on their own page', () => {
    mount('public');

    expect(opened.current).toBeUndefined();
  });

  it('follows an explicit choice over the visibility', () => {
    mount('direct', false);

    expect(opened.current).toBeUndefined();
  });
});
