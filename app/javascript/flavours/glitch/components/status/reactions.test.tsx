import { useCallback } from 'react';

import { IntlProvider } from 'react-intl';

import { fromJS, Map as ImmutableMap } from 'immutable';

import { fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import {
  addReaction,
  removeReaction,
} from '@/flavours/glitch/actions/interactions';
import { useAppSelector } from '@/flavours/glitch/store';
import type { RootState } from '@/flavours/glitch/store';

import {
  selectRedesignReactions,
  StatusReactionPicker,
  StatusRedesignReactions,
} from './reactions';

const mocks = vi.hoisted(() => ({
  signedIn: true,
  enabled: true,
  visible: 3,
  dispatch: vi.fn(),
}));

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppSelector: vi.fn(),
  useAppDispatch: () => mocks.dispatch,
}));
vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({ signedIn: mocks.signedIn, permissions: 0 }),
}));
vi.mock('@/flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal()),
  get reactionsEnabled() {
    return mocks.enabled;
  },
  get visibleReactions() {
    return mocks.visible;
  },
}));
vi.mock('@/flavours/glitch/actions/interactions', async (importOriginal) => ({
  ...(await importOriginal()),
  addReaction: vi.fn(),
  removeReaction: vi.fn(),
}));
vi.mock('@/flavours/glitch/features/compose/redesign/emoji', () => ({
  ComposeEmojiButton: ({
    onPick,
    disabled,
  }: {
    onPick: (emoji: object) => void;
    disabled: boolean;
  }) => {
    const handleClick = useCallback(() => {
      onPick({ id: ':custom:', imageUrl: '/emoji.png' });
    }, [onPick]);
    return (
      <button type='button' disabled={disabled} onClick={handleClick}>
        Pick reaction
      </button>
    );
  },
}));
vi.mock('../status_reactions', () => ({
  StatusReactions: ({
    canReact,
    addReaction: add,
    removeReaction: remove,
    statusId,
  }: {
    canReact: boolean;
    addReaction: (id: string, name: string) => void;
    removeReaction: (id: string, name: string) => void;
    statusId: string;
  }) => {
    const handleAdd = useCallback(() => {
      add(statusId, '🌸');
    }, [add, statusId]);
    const handleRemove = useCallback(() => {
      remove(statusId, '🌸');
    }, [remove, statusId]);
    return (
      <div data-testid='reactions' data-enabled={canReact}>
        <button type='button' onClick={handleAdd}>
          Add
        </button>
        <button type='button' onClick={handleRemove}>
          Remove
        </button>
      </div>
    );
  },
}));

const state = {
  statuses: fromJS({
    '1': {
      reactions: [
        { name: '🌸', count: 1, users: [{ id: '2', display_name: 'Old' }] },
      ],
    },
  }),
  accounts: ImmutableMap({
    '2': ImmutableMap({ id: '2', display_name: 'Updated' }),
  }),
} as unknown as RootState;

beforeEach(() => {
  vi.clearAllMocks();
  mocks.signedIn = true;
  mocks.enabled = true;
  mocks.visible = 3;
  vi.mocked(useAppSelector).mockImplementation((selector) => selector(state));
});

it('refreshes reaction users from the shared account cache', () => {
  const reactions = selectRedesignReactions(state, '1');
  expect(reactions?.getIn([0, 'users', 0, 'display_name'])).toBe('Updated');
});

it('lets ordinary signed-in users react without an administrative permission', () => {
  render(<StatusRedesignReactions statusId='1' />);
  expect(screen.getByTestId('reactions').getAttribute('data-enabled')).toBe(
    'true',
  );
  fireEvent.click(screen.getByText('Add'));
  fireEvent.click(screen.getByText('Remove'));
  expect(addReaction).toHaveBeenCalledWith('1', '🌸');
  expect(removeReaction).toHaveBeenCalledWith('1', '🌸');
});

it('retains existing reactions but hides the picker when reactions are disabled', () => {
  mocks.enabled = false;
  render(
    <>
      <StatusRedesignReactions statusId='1' />
      <StatusReactionPicker statusId='1' />
    </>,
  );
  expect(screen.getByTestId('reactions').getAttribute('data-enabled')).toBe(
    'false',
  );
  expect(screen.queryByText('Pick reaction')).toBeNull();
  fireEvent.click(screen.getByText('Add'));
  expect(addReaction).not.toHaveBeenCalled();
});

it('prevents logged-out mutation through chips and the picker', () => {
  mocks.signedIn = false;
  render(
    <>
      <StatusRedesignReactions statusId='1' />
      <StatusReactionPicker statusId='1' />
    </>,
  );
  fireEvent.click(screen.getByText('Add'));
  fireEvent.click(screen.getByText('Remove'));
  fireEvent.click(screen.getByText('Pick reaction'));
  expect(addReaction).not.toHaveBeenCalled();
  expect(removeReaction).not.toHaveBeenCalled();
});

it('uses the custom emoji identifier and URL for a picker selection', () => {
  render(
    <IntlProvider locale='en'>
      <StatusReactionPicker statusId='1' />
    </IntlProvider>,
  );
  fireEvent.click(screen.getByText('Pick reaction'));
  expect(addReaction).toHaveBeenCalledWith('1', 'custom', '/emoji.png');
});

it('honors the configured reaction visibility count', () => {
  mocks.visible = 0;
  render(<StatusRedesignReactions statusId='1' />);
  expect(screen.queryByTestId('reactions')).toBeNull();
});
