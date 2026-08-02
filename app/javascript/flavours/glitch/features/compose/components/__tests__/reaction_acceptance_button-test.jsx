import { IntlProvider } from 'react-intl';

import { Map as ImmutableMap } from 'immutable';

import { render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import { useAppSelector } from 'flavours/glitch/store';

import { ReactionAcceptanceButton } from '../reaction_acceptance_button';

vi.mock('flavours/glitch/store', () => ({
  useAppSelector: vi.fn(),
  useAppDispatch: () => vi.fn(),
}));

vi.mock('@/flavours/glitch/components/dropdown_menu', () => ({
  Dropdown: ({ children }) => children,
}));

describe('<ReactionAcceptanceButton />', () => {
  let state;

  beforeEach(() => {
    state = ImmutableMap({
      local_settings: ImmutableMap({ show_reaction_acceptance: true }),
      compose: ImmutableMap({ reaction_acceptance: null }),
    });

    vi.mocked(useAppSelector).mockImplementation((selector) => selector(state));
  });

  it('can be hidden and shown without changing its hooks', () => {
    const { rerender } = render(
      <IntlProvider locale='en'>
        <ReactionAcceptanceButton />
      </IntlProvider>,
    );

    expect(screen.getByRole('button', { name: 'Accept all' })).toBeDefined();

    state = state.setIn(
      ['local_settings', 'show_reaction_acceptance'],
      false,
    );
    rerender(
      <IntlProvider locale='en'>
        <ReactionAcceptanceButton />
      </IntlProvider>,
    );

    expect(screen.queryByRole('button')).toBeNull();

    state = state.setIn(
      ['local_settings', 'show_reaction_acceptance'],
      true,
    );
    rerender(
      <IntlProvider locale='en'>
        <ReactionAcceptanceButton />
      </IntlProvider>,
    );

    expect(screen.getByRole('button', { name: 'Accept all' })).toBeDefined();
  });
});
