import { IntlProvider } from 'react-intl';

import { Route, Router, useParams } from 'react-router-dom';

import { cleanup, render, screen, waitFor } from '@testing-library/react';
import { createMemoryHistory } from 'history';
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { Provider } from 'react-redux';

import { accountFactoryAPI } from '@/testing/factories';
import { store } from 'flavours/glitch/store';

import AntennaEdit from '../edit';

await vi.hoisted(() => import('../../chat/testing/match_media'));

vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => null,
}));

vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const antennaJSON = (id, overrides = {}) => ({
  id,
  title: `Antenna ${id}`,
  available: true,
  with_media_only: false,
  ignore_reblog: false,
  keywords: [],
  exclude_keywords: [],
  accounts: [],
  exclude_accounts: [],
  domains: [],
  exclude_domains: [],
  tags: [],
  exclude_tags: [],
  ...overrides,
});

const accountsById = {
  10: accountFactoryAPI({ id: '10', acct: 'alice', username: 'alice' }),
  11: accountFactoryAPI({ id: '11', acct: 'bob@remote.example', username: 'bob' }),
};

const antennas = {};

const server = setupServer(
  http.get('*/api/v1/antennas/:id', ({ params }) =>
    antennas[params.id]
      ? HttpResponse.json(antennas[params.id])
      : HttpResponse.json({ error: 'Record not found' }, { status: 404 }),
  ),
  http.get('*/api/v1/accounts', ({ request }) => {
    const ids = new URL(request.url).searchParams.getAll('id[]');
    return HttpResponse.json(ids.map((id) => accountsById[id]).filter(Boolean));
  }),
);

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'bypass' });
});

afterEach(() => {
  cleanup();
  server.resetHandlers();
});

afterAll(() => {
  server.close();
});

const EditRoute = () => {
  const params = useParams();
  return <AntennaEdit params={params} multiColumn />;
};

const renderEdit = (id) => {
  const history = createMemoryHistory({ initialEntries: [`/antennas/${id}/edit`] });

  render(
    <Provider store={store}>
      <IntlProvider locale='en'>
        <Router history={history}>
          <Route path='/antennas/:id/edit' component={EditRoute} />
        </Router>
      </IntlProvider>
    </Provider>,
  );

  return history;
};

describe('AntennaEdit', () => {
  it('shows saved accounts by their handle instead of their id', async () => {
    antennas['1'] = antennaJSON('1', { accounts: ['10'], exclude_accounts: ['11'] });
    renderEdit('1');

    await waitFor(() => {
      expect(screen.getByText('@alice')).toBeTruthy();
    });
    expect(screen.getByText('@bob@remote.example')).toBeTruthy();
    expect(screen.queryByText('10')).toBeNull();
    expect(screen.queryByText('11')).toBeNull();
  });
});
