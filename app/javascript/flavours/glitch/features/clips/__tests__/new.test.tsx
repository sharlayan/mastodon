import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import { cleanup, render, screen } from '@testing-library/react';
import { createMemoryHistory } from 'history';

import NewClipWrapper from '../new';

const mocks = vi.hoisted(() => ({
  clip: { current: undefined as null | undefined },
  dispatch: vi.fn(() => Promise.resolve()),
}));

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: () => mocks.clip.current,
}));

vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({ signedIn: true }),
}));

vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => null,
}));

vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

describe('NewClipWrapper', () => {
  afterEach(() => {
    cleanup();
  });

  it('shows an error instead of loading forever when the clip is missing', () => {
    mocks.clip.current = null;
    const history = createMemoryHistory({ initialEntries: ['/clips/7/edit'] });

    render(
      <IntlProvider locale='en'>
        <Router history={history}>
          <Route path='/clips/:id/edit'>
            <NewClipWrapper multiColumn />
          </Route>
        </Router>
      </IntlProvider>,
    );

    expect(screen.queryAllByRole('progressbar')).toHaveLength(0);
    expect(
      screen.getByText(/The requested page could not be found/),
    ).toBeTruthy();
  });
});
