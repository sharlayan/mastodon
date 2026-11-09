import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import {
  act,
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
  accountId: undefined as string | undefined,
  applyPageColorScheme: vi.fn(),
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
  PAGE_LIST_LIMIT: 20,
}));

vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({ accountId: mocks.accountId }),
}));

vi.mock('flavours/glitch/utils/theme', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  applyPageColorScheme: mocks.applyPageColorScheme,
}));

vi.mock('flavours/glitch/utils/page_blog_theme', () => ({
  pageBlogThemeNeedsReload: () => false,
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
    previousPage,
    nextPage,
  }: {
    page: ApiPageJSON;
    previousPage: ApiPageJSON | null;
    nextPage: ApiPageJSON | null;
    onMainToggle: () => void;
    onLikeToggle: () => void;
    onShare: () => void;
    onDelete: () => void;
  }) => (
    <div>
      <span data-testid='title'>{page.title}</span>
      <span data-testid='nav'>{`${previousPage?.id ?? '-'}|${nextPage?.id ?? '-'}`}</span>
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

const renderShow = (path = '/pages/a', multiColumn = true) => {
  const history = createMemoryHistory({ initialEntries: [path] });

  render(
    <IntlProvider locale='en'>
      <Router history={history}>
        <Route path='/pages/:id'>
          <PageShow multiColumn={multiColumn} />
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
    mocks.applyPageColorScheme.mockReset();
    mocks.accountId = '1';
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

  const alertTypes = () =>
    mocks.dispatch.mock.calls.map((call) => {
      const action = call[0] as {
        type: string;
        payload?: { message?: { id?: string } };
      };

      return action.payload?.message?.id ?? action.type;
    });

  it('shows an error when liking fails', async () => {
    mocks.apiLikePage.mockRejectedValue(new Error('network'));
    renderShow();

    fireEvent.click(await screen.findByText('like'));

    await waitFor(() => {
      expect(alertTypes()).toContain('alert.unexpected.message');
    });
  });

  it('shows an error when setting the main page fails', async () => {
    mocks.apiGetPage.mockResolvedValue(pageJSON('a'));
    mocks.apiSetMainPage.mockRejectedValue(new Error('network'));
    renderShow();

    fireEvent.click(await screen.findByText('main'));

    await waitFor(() => {
      expect(alertTypes()).toContain('alert.unexpected.message');
    });
  });

  it('shows an error when deleting fails', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    mocks.apiDeletePage.mockRejectedValue(new Error('network'));
    const history = renderShow();

    fireEvent.click(await screen.findByText('delete'));

    await waitFor(() => {
      expect(alertTypes()).toContain('alert.unexpected.message');
    });
    expect(history.location.pathname).toBe('/pages/a');
  });

  it('ignores a cancelled native share', async () => {
    const share = vi.fn(() =>
      Promise.reject(new DOMException('cancelled', 'AbortError')),
    );
    Object.defineProperty(navigator, 'share', {
      configurable: true,
      value: share,
    });
    renderShow();

    fireEvent.click(await screen.findByText('share'));

    await waitFor(() => {
      expect(share).toHaveBeenCalled();
    });
    await act(() => Promise.resolve());
    expect(mocks.dispatch).not.toHaveBeenCalled();
    Reflect.deleteProperty(navigator, 'share');
  });

  it('does not say the link was copied when copying fails', async () => {
    const writeText = vi.fn(() => Promise.reject(new Error('denied')));
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    });
    renderShow();

    fireEvent.click(await screen.findByText('share'));

    await waitFor(() => {
      expect(alertTypes()).toContain('alert.unexpected.message');
    });
    expect(alertTypes()).not.toContain('pages.link_copied');
  });

  it('says the link was copied after copying succeeds', async () => {
    const writeText = vi.fn(() => Promise.resolve());
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    });
    renderShow();

    fireEvent.click(await screen.findByText('share'));

    await waitFor(() => {
      expect(alertTypes()).toContain('pages.link_copied');
    });
  });

  it('opens when site data access is blocked', async () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new DOMException('blocked', 'SecurityError');
    });
    renderShow();

    expect((await screen.findByTestId('title')).textContent).toBe('Page a');
  });

  it('ignores an unsupported stored color scheme', async () => {
    mocks.accountId = undefined;
    vi.spyOn(Storage.prototype, 'getItem').mockReturnValue('purple');
    mocks.apiGetPage.mockResolvedValue(
      pageJSON('a', {
        account: {
          acct: 'alice',
          pages_view: 'blog',
          noindex: true,
        } as unknown as ApiPageJSON['account'],
      }),
    );
    renderShow('/pages/a', false);

    await screen.findByTestId('title');

    expect(mocks.applyPageColorScheme).toHaveBeenCalled();
    expect(mocks.applyPageColorScheme).not.toHaveBeenCalledWith(
      'purple',
      expect.anything(),
    );
  });

  it('keeps the color scheme choice when saving it fails', async () => {
    mocks.accountId = undefined;
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new DOMException('blocked', 'SecurityError');
    });
    mocks.apiGetPage.mockResolvedValue(
      pageJSON('a', {
        account: {
          acct: 'alice',
          pages_view: 'blog',
          noindex: true,
        } as unknown as ApiPageJSON['account'],
      }),
    );
    renderShow('/pages/a', false);

    const select = await screen.findByRole('combobox');
    fireEvent.change(select, { target: { value: 'dark' } });

    expect((select as HTMLSelectElement).value).toBe('dark');
  });

  it('ignores a like response for a page that is no longer open', async () => {
    let resolveLike: (value: ApiPageJSON) => void = () => undefined;
    mocks.apiLikePage.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveLike = resolve;
        }),
    );
    const history = renderShow();

    fireEvent.click(await screen.findByText('like'));
    act(() => {
      history.push('/pages/b');
    });
    await waitFor(() => {
      expect(screen.getByTestId('title').textContent).toBe('Page b');
    });

    await act(async () => {
      resolveLike(pageJSON('a', { liked: true }));
      await Promise.resolve();
    });

    expect(screen.getByTestId('title').textContent).toBe('Page b');
  });

  it('does not link neighbours when the open page is missing from the fetched list', async () => {
    renderShow('/pages/x');

    await waitFor(() => {
      expect(screen.getByTestId('sidebar').textContent).toBe('x:-a:mainb:-');
    });
    expect(screen.getByTestId('nav').textContent).toBe('-|-');
  });

  it('does not link Booklet neighbours from a truncated page list', async () => {
    const booklet = (id: string, position: number) =>
      pageJSON(id, { booklet_id: 'b1', booklet_position: position });
    mocks.apiGetPage.mockResolvedValue(booklet('c', 2));
    mocks.apiGetAccountPages.mockResolvedValue([
      booklet('c', 2),
      booklet('d', 3),
      ...Array.from({ length: 18 }, (_, index) => pageJSON(`p${index}`)),
    ]);
    renderShow('/pages/c');

    await waitFor(() => {
      expect(screen.getByTestId('sidebar').textContent).toBe('c:-d:-');
    });
    expect(screen.getByTestId('nav').textContent).toBe('-|-');
  });

  it('links Booklet neighbours when the page list is complete', async () => {
    const booklet = (id: string, position: number) =>
      pageJSON(id, { booklet_id: 'b1', booklet_position: position });
    mocks.apiGetPage.mockResolvedValue(booklet('c', 2));
    mocks.apiGetAccountPages.mockResolvedValue([
      booklet('c', 2),
      booklet('d', 3),
      booklet('e', 1),
    ]);
    renderShow('/pages/c');

    await waitFor(() => {
      expect(screen.getByTestId('nav').textContent).toBe('e|d');
    });
  });
});
