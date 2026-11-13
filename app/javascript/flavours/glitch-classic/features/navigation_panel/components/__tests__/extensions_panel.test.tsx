import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router';

import { fromJS } from 'immutable';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { openModal } from 'flavours/glitch-classic/actions/modal';

import { ExtensionsPanel } from '../extensions_panel';

const context = vi.hoisted(() => ({
  dispatch: vi.fn(),
  flags: {
    circlesEnabled: false,
    clipsEnabled: false,
    driveEnabled: true,
    pagesEnabled: false,
  },
}));

vi.mock('flavours/glitch-classic/initial_state', () => context.flags);
vi.mock('flavours/glitch-classic/sharlayan/roleplay', () => ({
  adminTimelineOwnerViewer: false,
  softHideDeletion: false,
}));
vi.mock('flavours/glitch-classic/store', () => ({
  useAppDispatch: () => context.dispatch,
  useAppSelector: (
    selector: (state: { local_settings: ReturnType<typeof fromJS> }) => unknown,
  ) => selector({ local_settings: fromJS({}) }),
}));

const renderPanel = () =>
  render(
    <IntlProvider locale='en'>
      <MemoryRouter>
        <ExtensionsPanel />
      </MemoryRouter>
    </IntlProvider>,
  );

afterEach(() => {
  cleanup();
  context.dispatch.mockClear();
  context.flags.driveEnabled = true;
});

describe('ExtensionsPanel Drive entry', () => {
  it('opens the Drive manager modal instead of navigating, and hides the entry when Drive is off', () => {
    renderPanel();
    fireEvent.click(
      screen.getByRole('button', { name: 'Expand extensions menu' }),
    );
    fireEvent.click(screen.getByText('Drive'));

    expect(context.dispatch).toHaveBeenCalledWith(
      openModal({ modalType: 'DRIVE_MANAGER', modalProps: {} }),
    );

    cleanup();
    context.flags.driveEnabled = false;
    renderPanel();
    fireEvent.click(
      screen.getByRole('button', { name: 'Expand extensions menu' }),
    );

    expect(screen.queryByText('Drive')).toBeNull();
  });
});
