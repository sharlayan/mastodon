import { IntlProvider } from 'react-intl';

import { Router } from 'react-router-dom';

import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { createMemoryHistory } from 'history';
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { Provider } from 'react-redux';

import { store } from 'flavours/glitch/store';

import AntennaTimeline from '..';

await vi.hoisted(() => import('../../chat/testing/match_media'));

const mocks = vi.hoisted(() => ({ deleteStatus: 200 }));

vi.mock('flavours/glitch/actions/streaming', async (importOriginal) => ({
  ...(await importOriginal()),
  connectAntennaStream: () => () => () => {},
}));

vi.mock('flavours/glitch/components/column/header', async () => {
  const { default: PropTypes } = await import('prop-types');
  const ColumnHeader = ({ children }) => <div>{children}</div>;
  ColumnHeader.propTypes = { children: PropTypes.node };

  return { ColumnHeader };
});

vi.mock('flavours/glitch/features/ui/containers/status_list_container', () => ({
  default: () => null,
}));

vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const server = setupServer(
  http.get('*/api/v1/antennas/7', () => HttpResponse.json({ id: '7', title: 'Art' })),
  http.get('*/api/v1/timelines/antenna/7', () => HttpResponse.json([])),
  http.delete('*/api/v1/antennas/7', () =>
    mocks.deleteStatus === 200
      ? HttpResponse.json({})
      : HttpResponse.json({ error: 'Something went wrong' }, { status: mocks.deleteStatus }),
  ),
);

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'bypass' });
});

afterEach(() => {
  cleanup();
});

afterAll(() => {
  server.close();
});

const confirmDeletion = async () => {
  fireEvent.click(await screen.findByRole('button', { name: /Delete antenna/ }));
  store.getState().modal.get('stack').get(0).get('modalProps').onConfirm();
};

const renderTimeline = () => {
  const history = createMemoryHistory({ initialEntries: ['/antennas/7'] });

  render(
    <Provider store={store}>
      <IntlProvider locale='en'>
        <Router history={history}>
          <AntennaTimeline params={{ id: '7' }} multiColumn />
        </Router>
      </IntlProvider>
    </Provider>,
  );

  return history;
};

describe('AntennaTimeline', () => {
  it('stays on the antenna and shows an error when deletion fails', async () => {
    mocks.deleteStatus = 500;
    const history = renderTimeline();
    const alertCount = store.getState().alerts.length;

    await confirmDeletion();

    await waitFor(() => {
      expect(store.getState().alerts.length).toBe(alertCount + 1);
    });
    await new Promise((resolve) => { setTimeout(resolve, 0); });
    expect(history.location.pathname).toBe('/antennas/7');
  });

  it('leaves the antenna after a successful deletion', async () => {
    mocks.deleteStatus = 200;
    const history = renderTimeline();

    await confirmDeletion();

    await waitFor(() => {
      expect(history.location.pathname).toBe('/antennas');
    });
  });
});
