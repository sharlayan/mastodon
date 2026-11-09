import { IntlProvider } from 'react-intl';

import { Router } from 'react-router-dom';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { createMemoryHistory } from 'history';

import AccountPages from '../index';

const mocks = vi.hoisted(() => ({
  apiGetAccountPages: vi.fn(),
  apiGetAccountPageSeries: vi.fn(),
}));

vi.mock('@/flavours/glitch/api/pages', () => ({
  apiGetAccountPages: mocks.apiGetAccountPages,
  apiGetAccountPageSeries: mocks.apiGetAccountPageSeries,
  PAGE_LIST_LIMIT: 20,
}));

vi.mock('@/flavours/glitch/hooks/useAccountId', () => ({
  useAccountId: () => '1',
}));

vi.mock('@/flavours/glitch/hooks/useAccount', () => ({
  useAccount: () => undefined,
}));

vi.mock('@/flavours/glitch/hooks/useAccountVisibility', () => ({
  useAccountVisibility: () => ({
    suspended: false,
    blockedBy: true,
    hidden: false,
  }),
}));

vi.mock('@/flavours/glitch/components/account_header', () => ({
  AccountHeader: () => null,
}));

vi.mock('@/flavours/glitch/components/column/back_button', () => ({
  ColumnBackButton: () => null,
}));

vi.mock('@/flavours/glitch/components/remote_hint', () => ({
  RemoteHint: () => null,
}));

describe('AccountPages', () => {
  afterEach(() => {
    cleanup();
  });

  it('shows an empty Booklets tab instead of loading forever for blocked accounts', () => {
    const history = createMemoryHistory({ initialEntries: ['/@alice/pages'] });

    render(
      <IntlProvider locale='en'>
        <Router history={history}>
          <AccountPages multiColumn />
        </Router>
      </IntlProvider>,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Booklets' }));

    expect(screen.queryAllByRole('progressbar')).toHaveLength(0);
    expect(screen.getByText('No Booklets yet.')).toBeTruthy();
    expect(mocks.apiGetAccountPageSeries).not.toHaveBeenCalled();
  });
});
