import { IntlProvider } from 'react-intl';

import { Router } from 'react-router-dom';

import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { createMemoryHistory } from 'history';
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { Provider } from 'react-redux';

import { store } from 'flavours/glitch/store';

import Antennas from '..';

await vi.hoisted(() => import('../../chat/testing/match_media'));

vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => null,
}));

vi.mock('flavours/glitch/components/scrollable_list', () => ({
  default: () => null,
}));

vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const server = setupServer(
  http.get('*/api/v1/antennas', () => HttpResponse.json([])),
  http.post('*/api/v1/antennas', () =>
    HttpResponse.json({ error: 'Validation failed: Too many antennas' }, { status: 422 }),
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

describe('Antennas', () => {
  it('shows an error and keeps the title when creating an antenna fails', async () => {
    render(
      <Provider store={store}>
        <IntlProvider locale='en'>
          <Router history={createMemoryHistory()}>
            <Antennas multiColumn />
          </Router>
        </IntlProvider>
      </Provider>,
    );

    const alertCount = store.getState().alerts.length;
    const input = screen.getByPlaceholderText('New antenna title');
    fireEvent.change(input, { target: { value: 'Art' } });
    fireEvent.submit(input.closest('form'));

    await waitFor(() => {
      expect(store.getState().alerts.length).toBe(alertCount + 1);
    });
    expect(input.value).toBe('Art');
  });
});
