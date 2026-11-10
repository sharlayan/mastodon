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
import { AxiosError } from 'axios';
import type { AxiosResponse } from 'axios';
import { createMemoryHistory } from 'history';

import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';

import { BookletEditor } from '../booklet_editor';
import PageEditor from '../editor';

const mocks = vi.hoisted(() => ({
  apiGetPage: vi.fn(),
  apiGetPageSeries: vi.fn(),
  apiCreatePage: vi.fn(),
  apiUpdatePage: vi.fn(),
  apiUpdatePageSeries: vi.fn(),
  apiSetBookletMainPage: vi.fn(),
}));

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppSelector: () => undefined,
}));

vi.mock('flavours/glitch/api/pages', () => ({
  apiGetPage: mocks.apiGetPage,
  apiGetPageSeries: mocks.apiGetPageSeries,
  apiSetBookletMainPage: mocks.apiSetBookletMainPage,
  apiUnsetBookletMainPage: vi.fn(),
  apiCreatePage: mocks.apiCreatePage,
  apiUpdatePage: mocks.apiUpdatePage,
  apiCreatePageSeries: vi.fn(),
  apiUpdatePageSeries: mocks.apiUpdatePageSeries,
}));

vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => null,
}));

vi.mock('../components/image_upload_field', () => ({
  ImageUploadField: () => null,
}));

vi.mock('../components/editor_block', () => ({
  EditorBlock: () => null,
}));

vi.mock('../components/block_add_buttons', () => ({
  BlockAddButtons: () => null,
}));

const pageJSON = {
  id: 'a',
  name: 'existing-slug',
  title: 'Existing title',
  summary: null,
  booklet_id: null,
  booklet_position: 0,
  booklet_main: false,
  visibility: 'public',
  font: 'sans-serif',
  align_center: false,
  content: [],
  eye_catching_media_attachment: null,
  attached_media: [],
  account: { acct: 'alice' },
} as unknown as ApiPageJSON;

const renderEditor = (path = '/pages/a/edit') => {
  const history = createMemoryHistory({ initialEntries: [path] });

  render(
    <IntlProvider locale='en'>
      <Router history={history}>
        <Route path={['/pages/:id/edit', '/pages/new']}>
          <PageEditor multiColumn />
        </Route>
      </Router>
    </IntlProvider>,
  );

  return history;
};

const notFound = () =>
  new AxiosError('not found', '404', undefined, undefined, {
    status: 404,
    statusText: 'Not Found',
    headers: {},
    data: {},
  } as AxiosResponse);

describe('PageEditor', () => {
  beforeEach(() => {
    mocks.apiGetPageSeries.mockResolvedValue([]);
    mocks.apiGetPage.mockReset();
    mocks.apiUpdatePage.mockReset();
    mocks.apiCreatePage.mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  it('shows a loading indicator and no save button until the page is loaded', async () => {
    let resolvePage: (value: ApiPageJSON) => void = () => undefined;
    mocks.apiGetPage.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolvePage = resolve;
        }),
    );
    renderEditor();

    expect(screen.getAllByRole('progressbar').length).toBeGreaterThan(0);
    expect(screen.queryByText('Save')).toBeNull();

    await act(async () => {
      resolvePage(pageJSON);
      await Promise.resolve();
    });

    expect(screen.getByLabelText<HTMLInputElement>(/Title/).value).toBe(
      'Existing title',
    );
    expect(
      screen.getByLabelText<HTMLInputElement>(/Display address/).value,
    ).toBe('existing-slug');
  });

  it('shows an error instead of an empty editor when the page cannot be loaded', async () => {
    mocks.apiGetPage.mockRejectedValue(notFound());
    renderEditor();

    await waitFor(() => {
      expect(screen.queryAllByRole('progressbar')).toHaveLength(0);
    });
    expect(screen.queryByText('Save')).toBeNull();
    expect(screen.queryByLabelText(/Title/)).toBeNull();
    expect(mocks.apiUpdatePage).not.toHaveBeenCalled();
  });

  it('offers a retry after a network error', async () => {
    mocks.apiGetPage.mockRejectedValueOnce(new Error('network'));
    mocks.apiGetPage.mockResolvedValueOnce(pageJSON);
    renderEditor();

    fireEvent.click(await screen.findByRole('button', { name: /Try again/ }));

    await waitFor(() => {
      expect(screen.getByLabelText<HTMLInputElement>(/Title/).value).toBe(
        'Existing title',
      );
    });
    expect(mocks.apiGetPage).toHaveBeenCalledTimes(2);
  });

  it('updates the created page instead of creating a duplicate when setting the Booklet main page fails', async () => {
    mocks.apiGetPageSeries.mockResolvedValue([
      { id: 'b1', title: 'Booklet one' },
    ]);
    mocks.apiCreatePage.mockResolvedValue({
      ...pageJSON,
      id: 'created',
      booklet_id: 'b1',
    });
    mocks.apiSetBookletMainPage.mockRejectedValueOnce(new Error('network'));
    mocks.apiUpdatePage.mockResolvedValue({
      ...pageJSON,
      id: 'created',
      booklet_id: 'b1',
      booklet_main: true,
    });
    renderEditor('/pages/new');

    fireEvent.change(screen.getByLabelText(/Title/), {
      target: { value: 'New title' },
    });
    await screen.findByRole('option', { name: 'Booklet one' });
    fireEvent.change(screen.getByLabelText(/^Booklet/), {
      target: { value: 'b1' },
    });
    fireEvent.click(screen.getByLabelText(/representative page/));
    fireEvent.click(screen.getByText('Save'));

    await waitFor(() => {
      expect(mocks.apiSetBookletMainPage).toHaveBeenCalledWith('created');
    });
    await waitFor(() => {
      expect(screen.getByText('Save').closest('button')?.disabled).toBe(false);
    });

    fireEvent.click(screen.getByText('Save'));

    await waitFor(() => {
      expect(mocks.apiUpdatePage).toHaveBeenCalledWith(
        'created',
        expect.objectContaining({ title: 'New title', booklet_id: 'b1' }),
      );
    });
    expect(mocks.apiCreatePage).toHaveBeenCalledTimes(1);
  });

  it('opens the editor for a new page without loading', () => {
    renderEditor('/pages/new');

    expect(screen.queryAllByRole('progressbar')).toHaveLength(0);
    expect(screen.getByText('Save')).toBeTruthy();
    expect(mocks.apiGetPage).not.toHaveBeenCalled();
  });
});

describe('BookletEditor', () => {
  const booklet = {
    id: 'b1',
    title: 'Saved booklet',
    description: 'Saved description',
    cover_media_attachment: null,
    displayed: true,
  };

  const renderBookletEditor = () => {
    const history = createMemoryHistory({
      initialEntries: ['/pages/booklets/b1/edit'],
    });

    render(
      <IntlProvider locale='en'>
        <Router history={history}>
          <Route path='/pages/booklets/:id/edit'>
            <BookletEditor multiColumn />
          </Route>
        </Router>
      </IntlProvider>,
    );
  };

  beforeEach(() => {
    mocks.apiGetPageSeries.mockReset();
    mocks.apiUpdatePageSeries.mockReset();
  });

  afterEach(() => {
    cleanup();
  });

  it('does not offer an empty form that can overwrite the Booklet when loading fails', async () => {
    mocks.apiGetPageSeries.mockRejectedValueOnce(new Error('network'));
    mocks.apiGetPageSeries.mockResolvedValueOnce([booklet]);
    renderBookletEditor();

    const retry = await screen.findByRole('button', { name: /Try again/ });

    expect(screen.queryByText('Save')).toBeNull();
    expect(screen.queryByLabelText(/Booklet title/)).toBeNull();

    fireEvent.click(retry);

    await waitFor(() => {
      expect(
        screen.getByLabelText<HTMLInputElement>(/Booklet title/).value,
      ).toBe('Saved booklet');
    });
    expect(mocks.apiUpdatePageSeries).not.toHaveBeenCalled();
  });

  it('shows a loading indicator and no save button until the Booklet is loaded', async () => {
    let resolveBooklets: (value: (typeof booklet)[]) => void = () => undefined;
    mocks.apiGetPageSeries.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveBooklets = resolve;
        }),
    );
    renderBookletEditor();

    expect(screen.getAllByRole('progressbar').length).toBeGreaterThan(0);
    expect(screen.queryByText('Save')).toBeNull();

    await act(async () => {
      resolveBooklets([booklet]);
      await Promise.resolve();
    });

    expect(screen.getByLabelText<HTMLInputElement>(/Booklet title/).value).toBe(
      'Saved booklet',
    );
  });
});
