import type { ReactNode } from 'react';

import { IntlProvider } from 'react-intl';

import { configureStore, createAction } from '@reduxjs/toolkit';
import { List as ImmutableList, Map as ImmutableMap } from 'immutable';
import { Provider } from 'react-redux';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from '@testing-library/react';

import { setComposeToStatusDraft } from '@/flavours/glitch/actions/status_drafts';

import { DraftButton } from '../draft_button';

const fetchDrafts = vi.hoisted(() => vi.fn<() => Promise<typeof drafts>>());

vi.mock('@/flavours/glitch/actions/status_drafts', () => ({
  fetchStatusDrafts: () => () => fetchDrafts(),
  setComposeToStatusDraft: vi.fn((draft: unknown) => ({
    type: 'LOAD_DRAFT',
    draft,
  })),
}));
vi.mock('@/flavours/glitch/store', async () => {
  const { useDispatch, useSelector } = await import('react-redux');
  return { useAppDispatch: useDispatch, useAppSelector: useSelector };
});
vi.mock('@/flavours/glitch/components/icon', () => ({ Icon: () => null }));
vi.mock('@/flavours/glitch/components/relative_timestamp', () => ({
  RelativeTimestamp: () => null,
}));
vi.mock('@/flavours/glitch/components/popover', () => ({
  Popover: ({
    isOpen,
    children,
  }: {
    isOpen: boolean;
    children: (props: { props: object; placement: string }) => ReactNode;
  }) => (isOpen ? children({ props: {}, placement: 'bottom' }) : null),
}));

const typeText = createAction<string>('TYPE_TEXT');
const drafts = ImmutableList([
  ImmutableMap<string, unknown>({
    id: 'saved-draft',
    params: ImmutableMap({ status: 'Saved text' }),
  }),
]);

const renderButton = () => {
  const initialState = {
    compose: ImmutableMap<string, unknown>({
      text: '',
      is_submitting: false,
      is_uploading: false,
      draft_save_request: null,
    }),
    local_settings: ImmutableMap({ show_draft_button: true }),
    status_drafts: ImmutableMap({ items: ImmutableList() }),
  };
  const store = configureStore({
    reducer: (state: typeof initialState = initialState, action) =>
      typeText.match(action)
        ? { ...state, compose: state.compose.set('text', action.payload) }
        : state,
    middleware: (getDefaultMiddleware) =>
      getDefaultMiddleware({ serializableCheck: false, immutableCheck: false }),
  });
  const result = render(
    <Provider store={store}>
      <IntlProvider locale='en'>
        <DraftButton onSaveDraft={vi.fn()} />
      </IntlProvider>
    </Provider>,
  );

  return { ...result, store };
};

const startLoading = () => {
  fireEvent.click(screen.getByRole('button', { name: 'Draft' }));
  fireEvent.click(screen.getByRole('button', { name: 'Load' }));
};

beforeEach(() => {
  fetchDrafts.mockReset();
  vi.mocked(setComposeToStatusDraft).mockClear();
});
afterEach(cleanup);

describe('<DraftButton />', () => {
  it('loads a single draft when the picker remains open and the composer is unchanged', async () => {
    fetchDrafts.mockResolvedValue(drafts);
    renderButton();
    startLoading();

    await vi.waitFor(() => {
      expect(setComposeToStatusDraft).toHaveBeenCalledWith(drafts.first());
    });
  });

  it('ignores a late response after the picker is closed and reopened', async () => {
    let resolveDrafts: (value: typeof drafts) => void = () => undefined;
    fetchDrafts.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveDrafts = resolve;
        }),
    );
    renderButton();
    startLoading();
    fireEvent.click(screen.getByRole('button', { name: 'Draft' }));
    fireEvent.click(screen.getByRole('button', { name: 'Draft' }));

    await act(async () => {
      resolveDrafts(drafts);
      await Promise.resolve();
    });

    expect(setComposeToStatusDraft).not.toHaveBeenCalled();
    expect(
      screen
        .getByRole('button', { name: 'Draft' })
        .getAttribute('aria-expanded'),
    ).toBe('true');
  });

  it('preserves text typed while the draft request is pending', async () => {
    let resolveDrafts: (value: typeof drafts) => void = () => undefined;
    fetchDrafts.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveDrafts = resolve;
        }),
    );
    const { store } = renderButton();
    startLoading();

    act(() => {
      store.dispatch(typeText('New unsaved text'));
    });
    await act(async () => {
      resolveDrafts(drafts);
      await Promise.resolve();
    });

    expect(setComposeToStatusDraft).not.toHaveBeenCalled();
    expect(store.getState().compose.get('text')).toBe('New unsaved text');
  });

  it('ignores a response that arrives after the button is unmounted', async () => {
    let resolveDrafts: (value: typeof drafts) => void = () => undefined;
    fetchDrafts.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveDrafts = resolve;
        }),
    );
    const { unmount } = renderButton();
    startLoading();
    unmount();

    await act(async () => {
      resolveDrafts(drafts);
      await Promise.resolve();
    });

    expect(setComposeToStatusDraft).not.toHaveBeenCalled();
  });
});
