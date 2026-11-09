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

import PageEditor from '../editor';

const mocks = vi.hoisted(() => ({
  apiGetPage: vi.fn(),
  apiGetPageSeries: vi.fn(),
  apiCreatePage: vi.fn(),
  apiUpdatePage: vi.fn(),
}));

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppSelector: () => undefined,
}));

vi.mock('flavours/glitch/api/pages', () => ({
  apiGetPage: mocks.apiGetPage,
  apiGetPageSeries: mocks.apiGetPageSeries,
  apiSetBookletMainPage: vi.fn(),
  apiUnsetBookletMainPage: vi.fn(),
  apiCreatePage: mocks.apiCreatePage,
  apiUpdatePage: mocks.apiUpdatePage,
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

  it('opens the editor for a new page without loading', () => {
    renderEditor('/pages/new');

    expect(screen.queryAllByRole('progressbar')).toHaveLength(0);
    expect(screen.getByText('Save')).toBeTruthy();
    expect(mocks.apiGetPage).not.toHaveBeenCalled();
  });
});
