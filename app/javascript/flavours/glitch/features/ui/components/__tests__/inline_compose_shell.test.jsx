import PropTypes from 'prop-types';
import { IntlProvider } from 'react-intl';

import { fromJS } from 'immutable';
import { MemoryRouter } from 'react-router';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { apiRequestPut } from 'flavours/glitch/api';


const context = vi.hoisted(() => ({ dispatch: vi.fn(), displayState: 'hidden', tabs: [{ type: 'list', id: '5' }] }));
let immutableState;
let InlineComposeShell;

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
  inlineComposeTabs: context.tabs,
}));
vi.mock('flavours/glitch/actions/antennas', () => ({ fetchAntennas: vi.fn() }));
vi.mock('flavours/glitch/actions/lists_typed', () => ({ fetchLists: vi.fn() }));
vi.mock('flavours/glitch/api', () => ({ apiRequestPut: vi.fn() }));
vi.mock('flavours/glitch/actions/alerts', () => ({ showAlertForError: vi.fn(error => ({ type: 'TEST_ALERT', error })) }));
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
vi.mock('flavours/glitch/features/compose/form', () => {
  const ComposeForm = ({ className }) => <form className={className}><textarea id='composer-text' aria-label='Redesign composer' /></form>;
  ComposeForm.propTypes = { className: PropTypes.string };
  return { ComposeForm };
});

const renderShell = () => render(
  <MemoryRouter initialEntries={['/home']}>
    <IntlProvider locale='en'>
      <InlineComposeShell />
      {context.displayState === 'showing' && <textarea id='composer-text' aria-label='Floating composer' />}
    </IntlProvider>
  </MemoryRouter>,
);

describe('inline composer shell', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    vi.resetModules();
    ({ InlineComposeShell } = await import('../inline_compose_shell'));
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

  it('renders the typed composer in the feed without the legacy lifecycle', async () => {
    renderShell();

    expect(await screen.findByRole('textbox', { name: 'Redesign composer' })).toBeTruthy();
    expect(document.querySelectorAll('#composer-text')).toHaveLength(1);
    expect(document.documentElement.classList.contains('inline-compose-mode')).toBe(false);
  });

  it('leaves a single textarea in the floating composer when it is open', () => {
    context.displayState = 'showing';
    renderShell();

    expect(screen.getByRole('textbox', { name: 'Floating composer' })).toBeTruthy();
    expect(screen.queryByRole('textbox', { name: 'Redesign composer' })).toBeNull();
    expect(document.querySelectorAll('#composer-text')).toHaveLength(1);
    expect(screen.getByRole('link', { name: 'Home' })).toBeTruthy();
  });

  it('keeps the composer minimized without losing feed tabs', () => {
    context.displayState = 'minimized';
    renderShell();

    expect(screen.queryByRole('textbox')).toBeNull();
    expect(screen.getByRole('link', { name: 'Home' })).toBeTruthy();
  });

  it('preserves expand-on-click for an empty typed composer', async () => {
    immutableState = immutableState.setIn(['local_settings', 'inline_compose_expand_on_click'], true);
    renderShell();

    const textarea = await screen.findByRole('textbox', { name: 'Redesign composer' });
    expect(textarea.closest('.inline-compose-form--collapsed')).toBeTruthy();
    fireEvent.focus(textarea);
    expect(textarea.closest('.inline-compose-form--collapsed')).toBeNull();
  });

  it('removes a feed tab with the Enter and space keys', () => {
    vi.mocked(apiRequestPut).mockResolvedValue({});

    for (const key of ['Enter', ' ']) {
      vi.mocked(apiRequestPut).mockClear();
      const { unmount } = renderShell();

      const remove = screen.getByRole('button', { name: 'Remove tab' });
      const notPrevented = fireEvent.keyDown(remove, { key });

      expect(notPrevented).toBe(false);
      expect(apiRequestPut).toHaveBeenCalledWith('v1/inline_compose_tabs', { tabs: [] });
      unmount();
    }
  });

  it('keeps saved feed tabs when the shell remounts', async () => {
    vi.mocked(apiRequestPut).mockResolvedValue({});
    const first = renderShell();

    fireEvent.click(screen.getByRole('button', { name: 'Remove tab' }));
    await vi.waitFor(() => expect(apiRequestPut).toHaveBeenCalledWith('v1/inline_compose_tabs', { tabs: [] }));
    first.unmount();

    renderShell();

    expect(screen.queryByRole('button', { name: 'Remove tab' })).toBeNull();
  });

  it('shows an alert when saving the feed tabs fails', async () => {
    const error = new Error('Request failed');
    vi.mocked(apiRequestPut).mockRejectedValue(error);
    renderShell();

    fireEvent.click(screen.getByRole('button', { name: 'Remove tab' }));

    await vi.waitFor(() => expect(context.dispatch).toHaveBeenCalledWith({ type: 'TEST_ALERT', error }));
  });
});
