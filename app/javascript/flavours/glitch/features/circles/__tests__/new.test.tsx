import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { createMemoryHistory } from 'history';

import NewCircleWrapper from '../new';

const mocks = vi.hoisted(() => ({
  circle: { current: undefined as null | undefined },
  dispatch: vi.fn<() => Promise<unknown>>(() => Promise.resolve()),
}));

vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => mocks.dispatch,
  useAppSelector: () => mocks.circle.current,
}));

vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({ signedIn: true }),
}));

vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => null,
}));

vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

vi.mock('flavours/glitch/components/avatar', () => ({ Avatar: () => null }));

vi.mock('../members', () => ({
  messages: {
    manageMembers: { id: 'circles.manage_members', defaultMessage: 'Members' },
  },
}));

describe('NewCircleWrapper', () => {
  afterEach(() => {
    cleanup();
  });

  it('shows an error instead of loading forever when the circle is missing', () => {
    mocks.circle.current = null;
    const history = createMemoryHistory({
      initialEntries: ['/circles/7/edit'],
    });

    render(
      <IntlProvider locale='en'>
        <Router history={history}>
          <Route path='/circles/:id/edit'>
            <NewCircleWrapper multiColumn />
          </Route>
        </Router>
      </IntlProvider>,
    );

    expect(screen.queryAllByRole('progressbar')).toHaveLength(0);
    expect(
      screen.getByText(/The requested page could not be found/),
    ).toBeTruthy();
  });

  it('prevents native form submission and duplicate creates while saving', () => {
    mocks.circle.current = undefined;
    mocks.dispatch.mockClear();
    mocks.dispatch.mockReturnValue(new Promise(() => undefined));
    const history = createMemoryHistory({ initialEntries: ['/circles/new'] });

    const { container } = render(
      <IntlProvider locale='en'>
        <Router history={history}>
          <Route path='/circles/new'>
            <NewCircleWrapper multiColumn />
          </Route>
        </Router>
      </IntlProvider>,
    );

    fireEvent.change(screen.getByRole('textbox'), {
      target: { value: 'Friends' },
    });

    const form = container.querySelector('form');
    if (!form) throw new Error('form missing');

    expect(fireEvent.submit(form)).toBe(false);
    fireEvent.submit(form);

    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
    expect(
      container
        .querySelector('button[type="submit"]')
        ?.hasAttribute('disabled'),
    ).toBe(true);
  });
});
