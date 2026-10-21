import { IntlProvider } from 'react-intl';

import { fromJS } from 'immutable';

import { fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import { openModal } from '@/flavours/glitch/actions/modal';
import { useAppSelector } from '@/flavours/glitch/store';
import type { RootState } from '@/flavours/glitch/store';

import { StatusActionBar } from './action_bar';

const mocks = vi.hoisted(() => ({
  signedIn: true,
  clips: true,
  dispatch: vi.fn(),
  reply: vi.fn(),
  quote: vi.fn(),
}));

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppSelector: vi.fn(),
  useAppDispatch: () => mocks.dispatch,
}));
vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({ signedIn: mocks.signedIn }),
}));
vi.mock('@/flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal()),
  quickBoosting: true,
  get clipsEnabled() {
    return mocks.clips;
  },
}));
vi.mock('@/flavours/glitch/hooks/useStatus', () => ({
  useAccountStatus: () => ({ id: '1', visibility: 'public', repliable: false }),
}));
vi.mock('@/flavours/glitch/hooks/useAccountId', () => ({
  useCurrentAccountId: () => 'self',
}));
vi.mock('../button/redesign', () => {
  const Button = ({
    children,
    tooltip,
    ...props
  }: {
    children: React.ReactNode;
    tooltip?: { text: React.ReactNode };
    onClick?: () => void;
    disabled?: boolean;
  }) => (
    <button type='button' onClick={props.onClick} disabled={props.disabled}>
      {tooltip?.text ?? children}
    </button>
  );
  return {
    Button,
    IconButton: Button,
    ToggleButton: Button,
    ToggleIconButton: Button,
  };
});
vi.mock('../menu', () => ({
  Menu: ({ children }: { children: React.ReactNode }) => children,
  MenuTrigger: () => <button type='button'>More</button>,
  MenuList: () => null,
  LegacyDropdownMenuItems: () => null,
}));
vi.mock('./hooks', () => ({
  useStatusContext: () => ({ contextType: 'home' }),
  useStatusMenuActions: () => [],
  useStatusIcons: () => ({
    reply: { title: 'Reply', action: mocks.reply },
    boost: { title: 'Boost' },
    like: { title: 'Favorite' },
    bookmark: { title: 'Bookmark' },
    quote: { title: 'Quote', action: mocks.quote, disabled: true },
  }),
}));
vi.mock('./reactions', () => ({
  StatusReactionPicker: () => <button type='button'>React</button>,
}));
vi.mock('./legacy/action_bar/remove_quote_hint', () => ({
  RemoveQuoteHint: ({
    children,
  }: {
    children: (dismiss: () => void) => React.ReactNode;
  }) => children(vi.fn()),
}));

function configure(order: string[] = [], hidden = {}) {
  const localSettings = fromJS({ status_action_bar: { order, hidden } });
  const state = fromJS({ local_settings: localSettings, statuses: {} });
  vi.mocked(useAppSelector).mockImplementation((selector) =>
    selector({
      statuses: state.get('statuses'),
      local_settings: localSettings,
      getIn: state.getIn.bind(state),
    } as unknown as RootState),
  );
}

function renderBar(onlyResponses = false) {
  render(
    <IntlProvider locale='en'>
      <StatusActionBar statusId='1' onlyResponses={onlyResponses} />
    </IntlProvider>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.signedIn = true;
  mocks.clips = true;
  configure();
});

it('preserves custom order and hidden actions', () => {
  configure(['clip', 'reaction', 'favourite', 'quote', 'bookmark'], {
    bookmark: true,
  });
  renderBar();
  expect(
    screen.getAllByRole('button').map((button) => button.textContent),
  ).toEqual([
    'Reply',
    'Boost',
    'Add to clip',
    'React',
    'Favorite',
    'Quote',
    'Share',
    'More',
  ]);
  fireEvent.click(screen.getByText('Add to clip'));
  expect(mocks.dispatch).toHaveBeenCalledWith(
    openModal({ modalType: 'CLIP_ADD', modalProps: { statusId: '1' } }),
  );
});

it('keeps reaction and clip controls on the detailed response bar', () => {
  renderBar(true);
  expect(screen.getByText('React')).not.toBeNull();
  expect(screen.getByText('Add to clip')).not.toBeNull();
  expect(screen.queryByText('Bookmark')).toBeNull();
  expect(screen.queryByText('More')).toBeNull();
});

it('hides clips when the server disables them', () => {
  mocks.clips = false;
  renderBar();
  expect(screen.queryByText('Add to clip')).toBeNull();
});

it('disables authenticated controls while logged out', () => {
  mocks.signedIn = false;
  renderBar();
  expect(screen.queryByText('Add to clip')).toBeNull();
  expect(screen.queryByText('Quote')).toBeNull();
  expect(
    screen.getByRole<HTMLButtonElement>('button', { name: 'Bookmark' })
      .disabled,
  ).toBe(true);
});

it('preserves reply and quote restrictions', () => {
  renderBar();
  fireEvent.click(screen.getByText('Reply'));
  fireEvent.click(screen.getByText('Quote'));
  expect(mocks.reply).not.toHaveBeenCalled();
  expect(mocks.quote).not.toHaveBeenCalled();
});
