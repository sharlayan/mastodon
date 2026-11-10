import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { createMemoryHistory } from 'history';

import { deleteClip } from 'flavours/glitch/actions/clips';

import ClipTimeline from '../timeline';

const mocks = vi.hoisted(() => {
  const state: { actions: unknown[]; deleteResult: unknown } = {
    actions: [],
    deleteResult: null,
  };

  return state;
});

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => (action: unknown) => {
    if (typeof action === 'function') {
      return Promise.resolve(mocks.deleteResult);
    }

    mocks.actions.push(action);
    return action;
  },
  useAppSelector: () => ({ id: '7', title: 'Clip', account_id: '1' }),
}));

vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({ accountId: '1' }),
}));

vi.mock('flavours/glitch/actions/timelines', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  expandClipTimeline: vi.fn(),
}));

vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
}));

vi.mock('flavours/glitch/features/ui/containers/status_list_container', () => ({
  default: () => null,
}));

vi.mock('../components/favourite_button', () => ({
  ClipFavouriteButton: () => null,
}));

vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

interface ConfirmAction {
  type: string;
  payload?: {
    modalType: string;
    modalProps: { onConfirm: () => void };
  };
}

const confirmModal = () =>
  mocks.actions.find(
    (action) =>
      (action as ConfirmAction | undefined)?.payload?.modalType === 'CONFIRM',
  ) as ConfirmAction | undefined;

const renderTimeline = () => {
  const history = createMemoryHistory({ initialEntries: ['/clips/7'] });

  render(
    <IntlProvider locale='en'>
      <Router history={history}>
        <Route path='/clips/:id'>
          <ClipTimeline multiColumn />
        </Route>
      </Router>
    </IntlProvider>,
  );

  return history;
};

describe('ClipTimeline', () => {
  afterEach(() => {
    cleanup();
    mocks.actions = [];
  });

  it('asks for confirmation and stays on the clip when deletion fails', async () => {
    mocks.deleteResult = deleteClip.rejected(null, 'request', { id: '7' });
    const history = renderTimeline();

    fireEvent.click(screen.getByRole('button', { name: /Delete clip/ }));

    const modal = confirmModal();
    expect(modal).toBeDefined();
    expect(history.location.pathname).toBe('/clips/7');

    modal?.payload?.modalProps.onConfirm();
    await Promise.resolve();
    await Promise.resolve();

    expect(history.location.pathname).toBe('/clips/7');
  });

  it('leaves the clip after a confirmed successful deletion', async () => {
    mocks.deleteResult = deleteClip.fulfilled(undefined, 'request', {
      id: '7',
    });
    const history = renderTimeline();

    fireEvent.click(screen.getByRole('button', { name: /Delete clip/ }));
    confirmModal()?.payload?.modalProps.onConfirm();

    await waitFor(() => {
      expect(history.location.pathname).toBe('/clips');
    });
  });
});
