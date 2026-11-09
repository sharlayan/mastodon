import { IntlProvider } from 'react-intl';

import { fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import { ReactionSummaryBar } from './reaction_summary_bar';

const summary = [
  {
    name: 'blob',
    count: 2,
    url: '/local.png',
    static_url: '/local.png',
    domain: '',
  },
  {
    name: 'blob',
    count: 1,
    url: '/remote.png',
    static_url: '/remote.png',
    domain: 'remote.tld',
  },
];

const renderBar = (activeFilter: string | null, onFilterChange = vi.fn()) => {
  render(
    <IntlProvider locale='en'>
      <ReactionSummaryBar
        summary={summary}
        activeFilter={activeFilter}
        onFilterChange={onFilterChange}
      />
    </IntlProvider>,
  );

  return onFilterChange;
};

const emojiButtons = () =>
  screen.getAllByRole('button').filter((button) => button.querySelector('img'));

describe('ReactionSummaryBar', () => {
  it('filters local and remote emoji with the same shortcode separately', () => {
    const onFilterChange = renderBar(null);
    emojiButtons().forEach((button) => fireEvent.click(button));

    expect(onFilterChange.mock.calls).toEqual([['blob'], ['blob@remote.tld']]);
  });

  it('highlights only the selected emoji', () => {
    renderBar('blob@remote.tld');

    expect(
      emojiButtons().map((button) => button.classList.contains('active')),
    ).toEqual([false, true]);
  });
});
