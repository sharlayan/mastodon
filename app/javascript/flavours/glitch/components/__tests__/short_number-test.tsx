import { IntlProvider } from 'react-intl';

import { render, screen } from '@testing-library/react';

import { AccountFollowersCount } from '../account_followers_count';
import { ShortNumber } from '../short_number';

function renderShortNumber(value: number) {
  return render(
    <IntlProvider locale='en'>
      <ShortNumber value={value} />
    </IntlProvider>,
  );
}

describe('ShortNumber Component', () => {
  it('does not abbreviate numbers under 1000', () => {
    renderShortNumber(999);
    expect(screen.getByText('999')).toBeDefined();
  });

  it('formats thousands correctly for 1000', () => {
    renderShortNumber(1000);
    expect(screen.getByText('1K')).toBeDefined();
  });

  it('truncates decimals for 1051', () => {
    renderShortNumber(1051);
    expect(screen.getByText('1K')).toBeDefined();
  });

  it('truncates decimals for 2999', () => {
    renderShortNumber(2999);
    expect(screen.getByText('2.9K')).toBeDefined();
  });

  it('truncates decimals for 9999', () => {
    renderShortNumber(9999);
    expect(screen.getByText('9.9K')).toBeDefined();
  });

  it('truncates decimals for 10501', () => {
    renderShortNumber(10501);
    expect(screen.getByText('10K')).toBeDefined();
  });

  it('truncates decimals for 11000', () => {
    renderShortNumber(11000);
    expect(screen.getByText('11K')).toBeDefined();
  });

  it('truncates decimals for 99999', () => {
    renderShortNumber(99999);
    expect(screen.getByText('99K')).toBeDefined();
  });

  it('truncates decimals for 100501', () => {
    renderShortNumber(100501);
    expect(screen.getByText('100K')).toBeDefined();
  });

  it('truncates decimals for 101000', () => {
    renderShortNumber(101000);
    expect(screen.getByText('101K')).toBeDefined();
  });

  it('truncates decimals for 999999', () => {
    renderShortNumber(999999);
    expect(screen.getByText('999K')).toBeDefined();
  });

  it('truncates decimals for 2999999', () => {
    renderShortNumber(2999999);
    expect(screen.getByText('2.9M')).toBeDefined();
  });

  it('truncates decimals for 9999999', () => {
    renderShortNumber(9999999);
    expect(screen.getByText('9.9M')).toBeDefined();
  });
});

describe('AccountFollowersCount Component', () => {
  it('replaces hidden counts without selecting a numeric plural and preserves visible counts', () => {
    const { getByTestId } = render(
      <IntlProvider
        locale='en'
        messages={{
          'account.followers_counter':
            '{count, plural, =0 {No followers} other {{counter} followers}}',
        }}
      >
        <div data-testid='hidden'>
          <AccountFollowersCount value={-1} />
        </div>
        <div data-testid='hidden-label'>
          <AccountFollowersCount value={-1} withLabel />
        </div>
        <div data-testid='zero'>
          <AccountFollowersCount value={0} />
        </div>
        <div data-testid='zero-label'>
          <AccountFollowersCount value={0} withLabel />
        </div>
        <div data-testid='positive'>
          <AccountFollowersCount value={1234} />
        </div>
        <div data-testid='positive-label'>
          <AccountFollowersCount value={1234} withLabel />
        </div>
        <div data-testid='negative-number'>
          <ShortNumber value={-1} />
        </div>
      </IntlProvider>,
    );

    expect(getByTestId('hidden').textContent).toBe('-');
    expect(getByTestId('hidden-label').textContent).toBe('Followers');
    expect(getByTestId('zero').textContent).toBe('0');
    expect(getByTestId('zero-label').textContent).toBe('No followers');
    expect(getByTestId('positive').textContent).toBe('1.2K');
    expect(getByTestId('positive-label').textContent).toBe('1.2K followers');
    expect(getByTestId('negative-number').textContent).toBe('-1');
  });
});
