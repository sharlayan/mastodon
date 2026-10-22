import PropTypes from 'prop-types';
import { IntlProvider } from 'react-intl';

import { fromJS } from 'immutable';
import { MemoryRouter } from 'react-router';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { mountCompose, unmountCompose } from 'flavours/glitch/actions/compose';

import { InlineComposeShell } from '../inline_compose_shell';

const context = vi.hoisted(() => ({ dispatch: vi.fn(), displayState: 'hidden' }));
let immutableState;

vi.mock('flavours/glitch/store', () => ({
  useAppDispatch: () => context.dispatch,
  useAppSelector: (selector) => selector({
    local_settings: immutableState.get('local_settings'),
    composer: { displayState: context.displayState },
    get: (key) => immutableState.get(key),
    getIn: (keys) => immutableState.getIn(keys),
  }),
}));
vi.mock('flavours/glitch/initial_state', () => ({
  me: '1',
  antennaEnabled: false,
  federatedTimelineEnabled: false,
  localTimelineEnabled: false,
  inlineComposeTabs: [],
}));
vi.mock('flavours/glitch/actions/antennas', () => ({ fetchAntennas: vi.fn() }));
vi.mock('flavours/glitch/actions/lists_typed', () => ({ fetchLists: vi.fn() }));
vi.mock('flavours/glitch/actions/compose', () => ({ mountCompose: vi.fn(), unmountCompose: vi.fn() }));
vi.mock('flavours/glitch/api', () => ({ apiRequestPut: vi.fn() }));
vi.mock('flavours/glitch/selectors/lists', () => ({ getOrderedLists: () => [] }));
vi.mock('flavours/glitch/components/icon', () => ({ Icon: () => null }));
vi.mock('flavours/glitch/components/loading_indicator', () => ({ LoadingIndicator: () => null }));
vi.mock('flavours/glitch/components/tab_list', () => {
  const TabList = ({ children }) => <div>{children}</div>;
  const TabLink = ({ children, to }) => <a href={to}>{children}</a>;
  TabList.propTypes = { children: PropTypes.node };
  TabLink.propTypes = { children: PropTypes.node, to: PropTypes.string };
  return { TabList, TabLink };
});
vi.mock('flavours/glitch/features/compose/containers/compose_form_container', () => ({
  default: () => <textarea aria-label='Legacy composer' />,
}));
vi.mock('flavours/glitch/features/compose/redesign', () => {
  const RedesignComposeForm = ({ className }) => <form className={className}><textarea id='composer-text' aria-label='Redesign composer' /></form>;
  RedesignComposeForm.propTypes = { className: PropTypes.string };
  return { RedesignComposeForm };
});

const renderShell = (redesign = false) => render(
  <MemoryRouter initialEntries={['/home']}>
    <IntlProvider locale='en'>
      <InlineComposeShell redesign={redesign} />
      {context.displayState === 'showing' && <textarea id='composer-text' aria-label='Floating composer' />}
    </IntlProvider>
  </MemoryRouter>,
);

describe('inline composer shell', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    context.displayState = 'hidden';
    immutableState = fromJS({
      local_settings: { inline_compose_timelines: true, inline_compose_expand_on_click: false },
      compose: {
        text: '',
        spoiler_text: '',
        in_reply_to: null,
        id: null,
        poll: null,
        quoted_status_id: null,
        media_attachments: [],
        is_submitting: false,
      },
      antennas: {},
    });
  });

  afterEach(cleanup);

  it('retains the legacy form and lifecycle when redesign is disabled', () => {
    const { unmount } = renderShell();

    expect(screen.getByRole('textbox', { name: 'Legacy composer' })).toBeTruthy();
    expect(mountCompose).toHaveBeenCalledOnce();
    expect(document.documentElement.classList.contains('inline-compose-mode')).toBe(true);
    unmount();
    expect(unmountCompose).toHaveBeenCalledOnce();
    expect(document.documentElement.classList.contains('inline-compose-mode')).toBe(false);
  });

  it('renders the typed composer in the feed without the legacy lifecycle', async () => {
    renderShell(true);

    expect(await screen.findByRole('textbox', { name: 'Redesign composer' })).toBeTruthy();
    expect(document.querySelectorAll('#composer-text')).toHaveLength(1);
    expect(screen.queryByRole('textbox', { name: 'Legacy composer' })).toBeNull();
    expect(mountCompose).not.toHaveBeenCalled();
    expect(document.documentElement.classList.contains('inline-compose-mode')).toBe(false);
  });

  it('leaves a single textarea in the floating composer when it is open', () => {
    context.displayState = 'showing';
    renderShell(true);

    expect(screen.getByRole('textbox', { name: 'Floating composer' })).toBeTruthy();
    expect(screen.queryByRole('textbox', { name: 'Redesign composer' })).toBeNull();
    expect(document.querySelectorAll('#composer-text')).toHaveLength(1);
    expect(screen.getByRole('link', { name: 'Home' })).toBeTruthy();
  });

  it('keeps the composer minimized without losing feed tabs', () => {
    context.displayState = 'minimized';
    renderShell(true);

    expect(screen.queryByRole('textbox')).toBeNull();
    expect(screen.getByRole('link', { name: 'Home' })).toBeTruthy();
  });

  it('preserves expand-on-click for an empty typed composer', async () => {
    immutableState = immutableState.setIn(['local_settings', 'inline_compose_expand_on_click'], true);
    renderShell(true);

    const textarea = await screen.findByRole('textbox', { name: 'Redesign composer' });
    expect(textarea.closest('.inline-compose-form--collapsed')).toBeTruthy();
    fireEvent.focus(textarea);
    expect(textarea.closest('.inline-compose-form--collapsed')).toBeNull();
  });
});
