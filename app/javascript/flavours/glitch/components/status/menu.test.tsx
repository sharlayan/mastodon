import { IntlProvider } from 'react-intl';

import { fromJS } from 'immutable';

import { fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import type { AccountStatusShape } from '@/flavours/glitch/models/status';
import { useAppSelector } from '@/flavours/glitch/store';
import type { RootState } from '@/flavours/glitch/store';

import { StatusContext, useStatusMenuActions } from './hooks';
import type { StatusContextType } from './types';

const mocks = vi.hoisted(() => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });
  return {
    dispatch: vi.fn(),
    conditions: {
      isPublic: true,
      isLocal: true,
      isLoggedIn: true,
      isMine: false,
    },
    interactions: {},
    roleplay: true,
    softHide: true,
    owner: true,
    deleteModal: true,
    deleteStatus: vi.fn((statusId: string) => ({
      type: 'DELETE_STATUS',
      statusId,
    })),
    removeFromAntenna: vi.fn((antennaId: string, statusId: string) => ({
      type: 'ANTENNA_REMOVE',
      antennaId,
      statusId,
    })),
  };
});

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppSelector: vi.fn(),
  useAppDispatch: () => mocks.dispatch,
}));
vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({ permissions: 0 }),
}));
vi.mock('@/flavours/glitch/hooks/useRelationship', () => ({
  useRelationship: () => undefined,
}));
vi.mock('@/flavours/glitch/selectors/statuses', async (importOriginal) => ({
  ...(await importOriginal()),
  selectStatusConditions: () => mocks.conditions,
  selectStatusInteractionsAllowed: () => mocks.interactions,
}));
vi.mock('@/flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal()),
  quickBoosting: false,
  clipsEnabled: false,
  get deleteModal() {
    return mocks.deleteModal;
  },
}));
vi.mock('@/flavours/glitch/sharlayan/roleplay', () => ({
  get roleplayMode() {
    return mocks.roleplay;
  },
  get softHideDeletion() {
    return mocks.softHide;
  },
  get adminTimelineOwnerViewer() {
    return mocks.owner;
  },
}));
vi.mock('@/flavours/glitch/actions/statuses', async (importOriginal) => ({
  ...(await importOriginal()),
  deleteStatus: mocks.deleteStatus,
}));
vi.mock('@/flavours/glitch/actions/antennas', async (importOriginal) => ({
  ...(await importOriginal()),
  removeStatusFromAntenna: mocks.removeFromAntenna,
}));

const status = {
  id: 'original-post',
  account: { id: 'author', acct: 'author', username: 'author' },
  visibility: 'public',
} as AccountStatusShape;

const Menu: React.FC<{
  value: AccountStatusShape;
  contextType?: StatusContextType;
}> = ({ value, contextType }) => {
  const menu = useStatusMenuActions({ status: value, contextType });
  return menu.map((item, index) =>
    item && 'action' in item ? (
      <button key={index} type='button' onClick={item.action}>
        {item.text}
      </button>
    ) : null,
  );
};

function renderMenu(value = status, contextType?: StatusContextType) {
  return render(
    <IntlProvider locale='en'>
      <StatusContext.Provider value={{ id: 'boost-wrapper', contextType }}>
        <Menu value={value} contextType={contextType} />
      </StatusContext.Provider>
    </IntlProvider>,
  );
}

function lastModal() {
  return mocks.dispatch.mock.calls.at(-1)?.[0] as {
    type: string;
    payload: {
      modalType: string;
      modalProps: {
        title?: string;
        statusId?: string;
        purge?: boolean;
        onConfirm?: () => void;
      };
    };
  };
}

describe('redesign custom status menu', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Object.assign(mocks.conditions, {
      isPublic: true,
      isLocal: true,
      isLoggedIn: true,
      isMine: false,
    });
    mocks.interactions = {};
    mocks.roleplay = true;
    mocks.softHide = true;
    mocks.owner = true;
    mocks.deleteModal = true;
    vi.mocked(useAppSelector).mockImplementation((selector) =>
      selector({
        antennas: fromJS({ 'antenna-1': { title: 'My antenna' } }),
      } as unknown as RootState),
    );
  });

  it('confirms antenna removal and removes the displayed wrapper entry', () => {
    renderMenu(status, 'antenna:antenna-1');
    fireEvent.click(
      screen.getByRole('button', { name: 'Remove from this antenna' }),
    );
    expect(lastModal().payload.modalProps.title).toBe(
      'Remove this post from My antenna?',
    );
    expect(mocks.removeFromAntenna).not.toHaveBeenCalled();
    lastModal().payload.modalProps.onConfirm?.();
    expect(mocks.removeFromAntenna).toHaveBeenCalledWith(
      'antenna-1',
      'boost-wrapper',
    );
  });

  it('keeps antenna removal out of other timelines', () => {
    renderMenu(status, 'home');
    expect(
      screen.queryByRole('button', { name: 'Remove from this antenna' }),
    ).toBeNull();
  });

  it.each(['loggedOut', 'remote', 'roleplayOff', 'softHideOff', 'notOwner'])(
    'does not expose RP deletion when %s',
    (gate) => {
      if (gate === 'loggedOut') mocks.conditions.isLoggedIn = false;
      if (gate === 'remote') mocks.conditions.isLocal = false;
      if (gate === 'roleplayOff') mocks.roleplay = false;
      if (gate === 'softHideOff') mocks.softHide = false;
      if (gate === 'notOwner') mocks.owner = false;
      renderMenu();
      expect(
        screen.queryByRole('button', { name: 'Delete (Admin)' }),
      ).toBeNull();
    },
  );

  it('routes admin soft deletion through the existing confirmation', () => {
    renderMenu();
    fireEvent.click(screen.getByRole('button', { name: 'Delete (Admin)' }));
    expect(lastModal().payload).toMatchObject({
      modalType: 'CONFIRM_DELETE_STATUS',
      modalProps: { statusId: 'original-post', purge: false },
    });
  });

  it('honors disabled confirmation for soft deletion', () => {
    mocks.deleteModal = false;
    renderMenu();
    fireEvent.click(screen.getByRole('button', { name: 'Delete (Admin)' }));
    expect(mocks.deleteStatus).toHaveBeenCalledWith('original-post');
  });

  it('always confirms purge and replaces own edit/delete/redraft actions', () => {
    mocks.conditions.isMine = true;
    mocks.interactions = { edit: true, delete: true, redraft: true };
    mocks.deleteModal = false;
    renderMenu({ ...status, rp_hidden: true });
    expect(screen.queryByRole('button', { name: 'Edit' })).toBeNull();
    expect(
      screen.queryByRole('button', { name: 'Delete & re-draft' }),
    ).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }));
    expect(lastModal().payload).toMatchObject({
      modalType: 'CONFIRM_DELETE_STATUS',
      modalProps: { statusId: 'original-post', purge: true },
    });
    expect(mocks.deleteStatus).not.toHaveBeenCalled();
  });
});
