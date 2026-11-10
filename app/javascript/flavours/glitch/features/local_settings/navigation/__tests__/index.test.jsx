import { IntlProvider } from 'react-intl';

import { render } from '@testing-library/react';

import LocalSettingsNavigation from '../index';

vi.hoisted(() => {
  window.matchMedia = () => ({ matches: false, addEventListener: () => {}, removeEventListener: () => {} });
});
vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal()),
  userThemesEnabled: true,
}));

describe('local settings navigation', () => {
  it('highlights only the user theme item on the user theme page', () => {
    const { container } = render(
      <IntlProvider locale='en'>
        <LocalSettingsNavigation index={9} onClose={vi.fn()} onNavigate={vi.fn()} />
      </IntlProvider>,
    );

    const active = container.querySelectorAll('.local-settings__navigation__item.active');
    expect(active).toHaveLength(1);
    expect(active[0].getAttribute('title')).toBe('User theme');
  });
});
