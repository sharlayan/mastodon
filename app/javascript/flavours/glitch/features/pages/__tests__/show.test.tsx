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

import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';

import PageShow from '../show';

await vi.hoisted(() => import('../../chat/testing/match_media'));

const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  apiGetPage: vi.fn(),
  apiUnlockPage: vi.fn(),
  apiGetAccountPages: vi.fn(),
  apiDeletePage: vi.fn(),
  apiLikePage: vi.fn(),
  apiUnlikePage: vi.fn(),
  apiSetMainPage: vi.fn(),
  apiUnsetMainPage: vi.fn(),
}));

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => mocks.dispatch,
}));

vi.mock('flavours/glitch/api/pages', () => ({
  apiGetPage: mocks.apiGetPage,
  apiUnlockPage: mocks.apiUnlockPage,
  apiGetAccountPages: mocks.apiGetAccountPages,
  apiDeletePage: mocks.apiDeletePage,
  apiLikePage: mocks.apiLikePage,
  apiUnlikePage: mocks.apiUnlikePage,
  apiSetMainPage: mocks.apiSetMainPage,
  apiUnsetMainPage: mocks.apiUnsetMainPage,
}));

vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({ accountId: '1' }),
}));

vi.mock('../components/page_show_header', () => ({
  PageShowHeader: () => null,
}));

vi.mock('../components/page_show_sidebar', () => ({
  PageShowSidebar: ({
    pages,
    position,
  }: {
    pages: ApiPageJSON[];
    position?: string;
  }) =>
    position === 'bottom' ? null : (
      <ul data-testid='sidebar'>
        {pages.map((item) => (
          <li key={item.id}>{`${item.id}:${item.is_main ? 'main' : '-'}`}</li>
        ))}
      </ul>
    ),
}));

vi.mock('../components/page_show_content', () => ({
  PageShowContent: ({
    page,
    onMainToggle,
    onLikeToggle,
    onShare,
    onDelete,
  }: {
    page: ApiPageJSON;
    onMainToggle: () => void;
    onLikeToggle: () => void;
    onShare: () => void;
    onDelete: () => void;
  }) => (
    <div>
      <span data-testid='title'>{page.title}</span>
      <button type='button' onClick={onMainToggle}>
        main
      </button>
      <button type='button' onClick={onLikeToggle}>
        like
      </button>
      <button type='button' onClick={onShare}>
        share
      </button>
      <button type='button' onClick={onDelete}>
        delete
      </button>
    </div>
  ),
}));

const pageJSON = (id: string, overrides: Partial<ApiPageJSON> = {}) =>
  ({
    id,
    name: `page-${id}`,
    title: `Page ${id}`,
    account_id: '1',
    account: { acct: 'alice', pages_view: 'default', noindex: true },
    visibility: 'public',
    is_main: false,
    liked: false,
    booklet_id: null,
    booklet_position: 0,
    content: [],
    attached_media: [],
    eye_catching_media_attachment: null,
    ...overrides,
  }) as unknown as ApiPageJSON;

const renderShow = (path = '/pages/a') => {
  const history = createMemoryHistory({ initialEntries: [path] });

  render(
    <IntlProvider locale='en'>
      <Router history={history}>
        <Route path='/pages/:id'>
          <PageShow multiColumn />
        </Route>
      </Router>
    </IntlProvider>,
  );

  return history;
};

describe('PageShow', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'ResizeObserver',
      class {
        observe() {
          return undefined;
        }
        disconnect() {
          return undefined;
        }
      },
    );
    mocks.dispatch.mockReset();
    mocks.apiGetPage.mockImplementation((id: string) =>
      Promise.resolve(pageJSON(id, { is_main: id === 'a' })),
    );
    mocks.apiGetAccountPages.mockResolvedValue([
      pageJSON('a', { is_main: true }),
      pageJSON('b'),
    ]);
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('does not mark the page as main after unsetting it', async () => {
    mocks.apiUnsetMainPage.mockResolvedValue(pageJSON('a', { is_main: false }));
    renderShow();

    await waitFor(() => {
      expect(screen.getByTestId('sidebar').textContent).toBe('a:mainb:-');
    });

    fireEvent.click(screen.getByText('main'));

    await waitFor(() => {
      expect(mocks.apiUnsetMainPage).toHaveBeenCalledWith('a');
    });
    await waitFor(() => {
      expect(screen.getByTestId('sidebar').textContent).toBe('a:-b:-');
    });
  });
});
