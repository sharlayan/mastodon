import { IntlProvider, useIntl } from 'react-intl';

import { fromJS } from 'immutable';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { openModal } from '@/flavours/glitch/actions/modal';

import NavigationPanelSettings from '../../page/navigation_panel';

import LocalSettingsNavigation from '../index';

vi.hoisted(() => {
  window.matchMedia = () => ({ matches: false, addEventListener: () => {}, removeEventListener: () => {} });
});
vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal()),
  userThemesEnabled: true,
  localTimelineEnabled: true,
}));

vi.mock('@/flavours/glitch/store', () => ({ useAppDispatch: () => vi.fn() }));
vi.mock('@/flavours/glitch/actions/modal', () => ({ openModal: vi.fn(() => ({ type: 'OPEN_MODAL' })) }));

const NavigationSettingsPage = props => <NavigationPanelSettings {...props} intl={useIntl()} />;

describe('local settings navigation', () => {
  afterEach(cleanup);

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

  it('changes the mobile local timeline option and includes it when resetting navigation defaults', () => {
    const onChange = vi.fn();
    const view = render(
      <IntlProvider locale='en'>
        <NavigationSettingsPage
          settings={fromJS({ navigation_panel: { order: [], hidden: {}, mobile_local_timeline: false } })}
          onChange={onChange}
        />
      </IntlProvider>,
    );
    const option = screen.getByRole('checkbox', { name: /Show the local timeline instead of search/ });
    expect(option.checked).toBe(false);
    expect(option.disabled).toBe(false);
    fireEvent.click(option);
    expect(onChange).toHaveBeenLastCalledWith(['navigation_panel', 'mobile_local_timeline'], true);

    view.rerender(
      <IntlProvider locale='en'>
        <NavigationSettingsPage
          settings={fromJS({ navigation_panel: { order: [], hidden: {}, mobile_local_timeline: true } })}
          onChange={onChange}
        />
      </IntlProvider>,
    );
    expect(screen.getByRole('checkbox', { name: /Show the local timeline instead of search/ }).checked).toBe(true);
    fireEvent.click(screen.getByRole('button', { name: 'Use defaults' }));
    const { modalProps } = vi.mocked(openModal).mock.calls.at(-1)[0];
    modalProps.onConfirm();
    expect(onChange).toHaveBeenLastCalledWith(['navigation_panel'], fromJS({ order: [], hidden: {}, mobile_local_timeline: false }));
  });
});
