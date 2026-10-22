import type { ReactNode } from 'react';
import { useCallback } from 'react';

import { IntlProvider } from 'react-intl';

import { createSelector } from '@reduxjs/toolkit';
import { fromJS } from 'immutable';
import type { Map as ImmutableMap } from 'immutable';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { ComposeCustomControls, ComposeMfmHint } from '../custom_controls';
import { ComposeCustomSettings } from '../custom_settings';
import { ComposeUploadButton, ComposeSideArmButton } from '../footer';
import { selectComposeSideArm } from '../selectors';

const context = vi.hoisted(() => ({
  dispatch: vi.fn(),
  flags: {
    circlesEnabled: true,
    clipsEnabled: true,
    driveEnabled: true,
    mfmAllowComposition: true,
    forceLocalOnly: false,
    me: 'me',
  },
}));

const makeState = () => ({
  compose: fromJS({
    id: null,
    text: '$[spin hello]',
    circle_id: null,
    clip_ids: [],
    scheduled_at: null,
    content_type: 'text/x-mfm',
    reaction_acceptance: null,
    advanced_options: { do_not_federate: false, threaded_mode: false },
    media_attachments: [],
    pending_media_attachments: 0,
    resetFileKey: 0,
  }),
  local_settings: fromJS({
    show_clip_choice: true,
    show_draft_button: true,
    show_schedule_button: true,
    show_content_type_choice: true,
    show_reaction_acceptance: true,
  }) as ImmutableMap<string, unknown>,
  statuses: fromJS({}),
  status_drafts: fromJS({
    items: [
      {
        id: 'saved-draft',
        updated_at: '2026-10-01T00:00:00Z',
        params: { status: 'Saved server draft' },
      },
    ],
  }),
  media_attachments: fromJS({ accept_content_types: ['image/png'] }),
  server: {
    server: {
      item: { configuration: { statuses: { max_media_attachments: 4 } } },
    },
  },
});

let state = makeState();

vi.mock('@/flavours/glitch/store', () => ({
  createAppSelector: createSelector,
  useAppDispatch: () => context.dispatch,
  useAppSelector: (selector: (value: typeof state) => unknown) =>
    selector(state),
}));
vi.mock('@/flavours/glitch/initial_state', () => context.flags);
vi.mock('@/flavours/glitch/reducers/slices/composer', () => ({
  submitComposer: (payload: unknown) => ({ type: 'SUBMIT_COMPOSER', payload }),
}));
vi.mock('@/flavours/glitch/actions/circles', () => ({
  fetchCircles: () => ({ type: 'FETCH_CIRCLES' }),
}));
vi.mock('@/flavours/glitch/actions/clips', () => ({
  fetchClips: () => ({ type: 'FETCH_CLIPS' }),
}));
vi.mock('@/flavours/glitch/actions/compose_typed', () => ({
  changeComposeCircle: (id: string | null) => ({ type: 'CHANGE_CIRCLE', id }),
}));
vi.mock('@/flavours/glitch/actions/compose', () => ({
  changeScheduledAt: (scheduledAt: string | null) => ({
    type: 'CHANGE_SCHEDULE',
    scheduledAt,
  }),
  changeComposeAdvancedOption: (name: string, value: boolean) => ({
    type: 'CHANGE_OPTION',
    name,
    value,
  }),
  changeComposeContentType: (contentType: string) => ({
    type: 'CHANGE_CONTENT_TYPE',
    contentType,
  }),
  addPoll: vi.fn(),
  uploadCompose: vi.fn(),
}));
vi.mock('@/flavours/glitch/actions/status_drafts', () => ({
  fetchStatusDrafts: () => ({ type: 'FETCH_DRAFTS' }),
  saveStatusDraft: () => ({ type: 'SAVE_DRAFT' }),
  setComposeToStatusDraft: (draft: unknown) => ({ type: 'LOAD_DRAFT', draft }),
}));
vi.mock('@/flavours/glitch/actions/modal', () => ({
  openModal: (payload: unknown) => ({ type: 'OPEN_MODAL', payload }),
}));
vi.mock('@/flavours/glitch/selectors/circles', () => ({
  getOrderedCircles: () => [{ id: 'circle', title: 'Friends' }],
}));
vi.mock('@/flavours/glitch/selectors/clips', () => ({
  getOrderedAccountClips: () => [{ id: 'clip' }],
}));
vi.mock('@/flavours/glitch/sharlayan/compose/state', () => ({
  changeReactionAcceptance: (value: string | null) => ({
    type: 'CHANGE_REACTIONS',
    value,
  }),
}));
vi.mock('@/flavours/glitch/components/relative_timestamp', () => ({
  RelativeTimestamp: () => <span>Updated</span>,
}));
vi.mock('../emoji', () => ({ ComposeEmojiButton: () => null }));
vi.mock('@/flavours/glitch/components/button/redesign', () => ({
  Button: ({
    children,
    onClick,
    disabled,
  }: {
    children: ReactNode;
    onClick?: () => void;
    disabled?: boolean;
  }) => (
    <button type='button' onClick={onClick} disabled={disabled}>
      {children}
    </button>
  ),
  IconButton: ({
    children,
    onClick,
    disabled,
  }: {
    children: ReactNode;
    onClick?: () => void;
    disabled?: boolean;
  }) => (
    <button type='button' onClick={onClick} disabled={disabled}>
      {children}
    </button>
  ),
}));
vi.mock('@/flavours/glitch/components/menu', () => ({
  Menu: ({ children }: { children: ReactNode }) => <div>{children}</div>,
  MenuList: ({ children }: { children: ReactNode }) => <div>{children}</div>,
  MenuItemGroup: ({ children }: { children: ReactNode }) => (
    <div>{children}</div>
  ),
  MenuItemDivider: () => <hr />,
  MenuTrigger: ({
    children,
    disabled,
  }: {
    children: ReactNode;
    disabled?: boolean;
  }) => (
    <button type='button' disabled={disabled}>
      {children}
    </button>
  ),
  MenuItem: ({
    children,
    onClick,
    disabled,
  }: {
    children: ReactNode;
    onClick?: () => void;
    disabled?: boolean;
  }) => (
    <button type='button' onClick={onClick} disabled={disabled}>
      {children}
    </button>
  ),
  MenuItemRadio: ({
    children,
    value,
    onChange,
    disabled,
  }: {
    children: ReactNode;
    value: string;
    onChange: (value: { value: string }) => void;
    disabled?: boolean;
  }) => {
    const handleClick = useCallback(() => {
      onChange({ value });
    }, [onChange, value]);
    return (
      <button type='button' disabled={disabled} onClick={handleClick}>
        {children}
      </button>
    );
  },
  MenuItemCheckbox: ({
    children,
    onChange,
    disabled,
  }: {
    children: ReactNode;
    onChange: () => void;
    disabled?: boolean;
  }) => (
    <button type='button' disabled={disabled} onClick={onChange}>
      {children}
    </button>
  ),
}));
vi.mock('@/flavours/glitch/components/popover', () => ({
  Popover: () => null,
}));
vi.mock('@/flavours/glitch/components/menu/card', () => ({
  MenuCard: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}));

const renderControls = (element: ReactNode) =>
  render(<IntlProvider locale='en'>{element}</IntlProvider>);

beforeEach(() => {
  vi.clearAllMocks();
  state = makeState();
  Object.assign(context.flags, {
    circlesEnabled: true,
    clipsEnabled: true,
    driveEnabled: true,
    mfmAllowComposition: true,
    forceLocalOnly: false,
  });
});
afterEach(cleanup);

describe('redesign custom compose controls', () => {
  it('selects circles, opens clip selection and loads or saves server drafts through existing actions', () => {
    renderControls(<ComposeCustomControls />);
    fireEvent.click(screen.getByRole('button', { name: 'Friends' }));
    fireEvent.click(screen.getByRole('button', { name: 'Select clip' }));
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));
    fireEvent.click(screen.getByRole('button', { name: 'Saved server draft' }));

    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'CHANGE_CIRCLE',
      id: 'circle',
    });
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'OPEN_MODAL',
      payload: { modalType: 'CLIP_ADD', modalProps: {} },
    });
    expect(context.dispatch).toHaveBeenCalledWith({ type: 'SAVE_DRAFT' });
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'LOAD_DRAFT',
      draft: state.status_drafts.getIn(['items', 0]),
    });
  });

  it('honors feature gates and hidden draft or schedule settings', () => {
    context.flags.circlesEnabled = false;
    context.flags.clipsEnabled = false;
    state.local_settings = fromJS({
      show_draft_button: false,
      show_schedule_button: false,
    });
    renderControls(<ComposeCustomControls />);
    expect(screen.queryByRole('button')).toBeNull();
    expect(context.dispatch).not.toHaveBeenCalled();
  });

  it('keeps scheduled editing available while disabling destination changes', () => {
    state.compose = state.compose
      .set('id', 'scheduled')
      .set('scheduled_at', '2026-12-01T12:00:00Z');
    state.local_settings = state.local_settings.set(
      'show_schedule_button',
      false,
    );
    renderControls(<ComposeCustomControls />);
    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Select circle' })
        .disabled,
    ).toBe(true);
    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Select clip' })
        .disabled,
    ).toBe(true);
    expect(screen.queryByRole('button', { name: 'Draft' })).toBeNull();
    expect(
      screen
        .getAllByRole<HTMLButtonElement>('button')
        .some(
          (button) =>
            !button.disabled && button.textContent.includes('12/1/26'),
        ),
    ).toBe(true);
  });

  it('changes formatting, federation, reactions and threaded mode through shared compose actions', () => {
    renderControls(<ComposeCustomSettings />);
    fireEvent.click(screen.getByRole('button', { name: 'MFM' }));
    fireEvent.click(screen.getByRole('button', { name: 'Local-only' }));
    fireEvent.click(screen.getByRole('button', { name: 'Likes only' }));
    fireEvent.click(
      screen.getByRole('button', { name: 'Enable threaded mode' }),
    );
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'CHANGE_CONTENT_TYPE',
      contentType: 'text/x-mfm',
    });
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'CHANGE_OPTION',
      name: 'do_not_federate',
      value: true,
    });
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'CHANGE_REACTIONS',
      value: 'likeOnly',
    });
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'CHANGE_OPTION',
      name: 'threaded_mode',
      value: true,
    });
  });

  it('respects formatting, reaction and forced-local gates', () => {
    context.flags.mfmAllowComposition = false;
    context.flags.forceLocalOnly = true;
    state.local_settings = state.local_settings.set(
      'show_reaction_acceptance',
      false,
    );
    renderControls(<ComposeCustomSettings />);
    expect(screen.queryByRole('button', { name: 'MFM' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Likes only' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Local-only' })).toBeNull();
  });

  it('opens the Drive and doodle modals from the upload menu', () => {
    renderControls(<ComposeUploadButton />);
    fireEvent.click(screen.getByRole('button', { name: 'Attach from drive' }));
    fireEvent.click(screen.getByRole('button', { name: 'Draw something' }));
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'OPEN_MODAL',
      payload: { modalType: 'DRIVE', modalProps: {} },
    });
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'OPEN_MODAL',
      payload: {
        modalType: 'DOODLE',
        modalProps: { noEsc: true, noClose: true },
      },
    });
  });

  it('hides Drive and disables the upload trigger for quoted posts', () => {
    context.flags.driveEnabled = false;
    renderControls(<ComposeUploadButton disabled />);
    expect(
      screen.queryByRole('button', { name: 'Attach from drive' }),
    ).toBeNull();
    expect(
      (
        screen.getAllByRole('button', {
          name: 'Add images, a video or an audio file',
        })[0] as HTMLButtonElement
      ).disabled,
    ).toBe(true);
  });

  it.each([
    ['copy', 'public', 'private'],
    ['restrict', 'public', 'private'],
    ['restrict', 'direct', 'direct'],
    ['none', 'public', 'public'],
  ] as const)('keeps the %s reply side-arm policy', (mode, base, expected) => {
    expect(selectComposeSideArm.resultFunc(false, base, mode, 'private')).toBe(
      expected,
    );
  });

  it('submits the configured side-arm visibility and hides it while editing', () => {
    state.local_settings = state.local_settings.set('side_arm', 'private');
    const { rerender } = renderControls(<ComposeSideArmButton />);
    fireEvent.click(screen.getByRole('button', { name: 'Followers' }));
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'SUBMIT_COMPOSER',
      payload: { overridePrivacy: 'private' },
    });
    state = { ...state, compose: state.compose.set('id', 'published') };
    rerender(
      <IntlProvider locale='en'>
        <ComposeSideArmButton />
      </IntlProvider>,
    );
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('previews the current MFM text and honors the hidden hint setting', () => {
    const { rerender } = renderControls(<ComposeMfmHint />);
    fireEvent.click(screen.getByRole('button', { name: 'Preview' }));
    expect(context.dispatch).toHaveBeenCalledWith({
      type: 'OPEN_MODAL',
      payload: {
        modalType: 'MFM_PREVIEW',
        modalProps: { text: '$[spin hello]' },
      },
    });
    state.local_settings = state.local_settings.set(
      'hide_mfm_compose_hint',
      true,
    );
    rerender(
      <IntlProvider locale='en'>
        <ComposeMfmHint />
      </IntlProvider>,
    );
    expect(screen.queryByRole('button', { name: 'Preview' })).toBeNull();
  });
});
