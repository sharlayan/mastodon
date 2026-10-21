import { fromJS } from 'immutable';

import { getSharlayanComposeSubmission } from '@/flavours/glitch/sharlayan/compose/submission';

import { composer, selectComposerIsChanged, submitComposer } from '../composer';

const mocks = vi.hoisted(() => ({ submit: vi.fn() }));

vi.mock('@/flavours/glitch/actions/compose', () => ({
  COMPOSE_DIRECT: 'COMPOSE_DIRECT',
  COMPOSE_FOCUS: 'COMPOSE_FOCUS',
  COMPOSE_MENTION: 'COMPOSE_MENTION',
  COMPOSE_REPLY: 'COMPOSE_REPLY',
  COMPOSE_SET_STATUS: 'COMPOSE_SET_STATUS',
  changeCompose: (text) => ({ type: 'COMPOSE_CHANGE', text }),
  clearComposeSuggestions: () => ({ type: 'COMPOSE_SUGGESTIONS_CLEAR' }),
  directCompose: () => ({ type: 'COMPOSE_DIRECT' }),
  resetCompose: () => ({ type: 'COMPOSE_RESET' }),
  submitCompose: mocks.submit,
}));
vi.mock('@/flavours/glitch/actions/compose_typed', () => ({
  PRIVATE_QUOTE_MODAL_ID: 'private-quote',
  changeComposeVisibility: vi.fn(),
  replyComposeById: vi.fn(),
}));
vi.mock('@/flavours/glitch/actions/statuses', () => ({ REDRAFT: 'REDRAFT' }));

const makeState = (composeOverrides = {}, settings = {}) => ({
  composer: { displayState: 'showing', pendingFocus: null, publishErrors: [] },
  compose: fromJS({
    text: 'A post',
    spoiler_text: '',
    spoiler: false,
    privacy: 'public',
    poll: null,
    quoted_status_id: null,
    media_attachments: [],
    pending_media_attachments: 0,
    advanced_options: { threaded_mode: false },
    clip_ids: [],
    ...composeOverrides,
  }),
  meta: fromJS({ me: 'me', missing_alt_text_modal: false }),
  statuses: fromJS({}),
  settings: fromJS({}),
  local_settings: fromJS(settings),
  server: { server: { item: { configuration: { statuses: { max_characters: 500 } } } } },
});

function runSubmit(state, options = {}) {
  const dispatch = vi.fn((action) => {
    if (typeof action === 'function') return action(dispatch, () => state);
    state.composer = composer(state.composer, action);
    return action;
  });
  dispatch(submitComposer(options));
  return dispatch;
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.submit.mockImplementation((onSuccess) => ({ type: 'TEST_SUBMIT', onSuccess }));
});

describe('redesign composer custom state', () => {
  it.each(['COMPOSE_SET_DRAFT', 'COMPOSE_SET_SCHEDULED'])('opens and focuses loaded content for %s', (type) => {
    expect(composer(undefined, { type })).toMatchObject({
      displayState: 'showing',
      pendingFocus: { selection: null },
    });
  });

  it.each(['draft_id', 'scheduled_at'])('keeps an empty saved source when %s is present', (field) => {
    expect(selectComposerIsChanged(makeState({ text: '', [field]: 'saved' }))).toBe(true);
  });

  it('preserves the shared reducer thread continuation after publishing', () => {
    const state = makeState({ advanced_options: { threaded_mode: true } });
    const dispatch = runSubmit(state, { overridePrivacy: 'private' });
    expect(mocks.submit.mock.calls[0][1]).toBe('private');
    state.compose = state.compose.set('text', '').set('in_reply_to', 'published-status');

    mocks.submit.mock.calls[0][0]({ id: 'published-status', url: '/post' });

    expect(dispatch.mock.calls.some(([action]) => action.type === 'COMPOSE_RESET')).toBe(false);
    expect(state.compose.get('in_reply_to')).toBe('published-status');
    expect(state.composer).toMatchObject({ displayState: 'showing', pendingFocus: { selection: null } });
  });

  it('closes the composer for a scheduled response without redirecting to a missing post URL', () => {
    const state = makeState({ scheduled_at: '2026-12-01T12:00:00Z' });
    const dispatch = runSubmit(state, { redirectOnSuccess: true });

    mocks.submit.mock.calls[0][0]({ id: 'scheduled-status', scheduled_at: '2026-12-01T12:00:00Z' });

    expect(dispatch.mock.calls.some(([action]) => action.type === 'COMPOSE_RESET')).toBe(true);
    expect(state.composer.displayState).toBe('hidden');
  });

  it.each(['is_submitting', 'is_uploading', 'is_changing_upload'])('does not submit during %s', (field) => {
    runSubmit(makeState({ [field]: true }));
    expect(mocks.submit).not.toHaveBeenCalled();
  });

  it('counts the always visible content warning toward the limit', () => {
    const state = makeState({ text: 'a'.repeat(499), spoiler_text: 'cw' }, { always_show_spoilers_field: true });
    runSubmit(state);
    expect(mocks.submit).not.toHaveBeenCalled();
    expect(state.composer.publishErrors).toEqual(['too-long']);
  });

  it.each(['public', 'private', 'direct'])('forwards the %s side-arm through shared Circle and quote restrictions', (overridePrivacy) => {
    const state = makeState({ circle_id: 'circle', quote_policy: 'public', advanced_options: { do_not_federate: true, threaded_mode: true } });
    runSubmit(state, { overridePrivacy });
    expect(mocks.submit).toHaveBeenCalledWith(expect.any(Function), overridePrivacy);
    const submission = getSharlayanComposeSubmission({ getState: () => fromJS({ compose: state.compose }), effectiveStatusId: null, overridePrivacy: mocks.submit.mock.calls[0][1] });
    expect(submission).toMatchObject({ circleId: null, visibility: overridePrivacy, quoteApprovalPolicy: overridePrivacy === 'public' ? 'public' : 'nobody' });
    expect(state.compose.getIn(['advanced_options', 'do_not_federate'])).toBe(true);
    expect(state.compose.get('privacy')).toBe('public');
  });

  it('uses side-arm visibility for private quote confirmation and preserves it', () => {
    const state = makeState({ quoted_status_id: 'quoted' });
    state.statuses = fromJS({ quoted: { account: 'other' } });
    const dispatch = runSubmit(state, { overridePrivacy: 'private' });
    const modal = dispatch.mock.calls.find(([action]) => action.type === 'MODAL_OPEN')[0];
    expect(modal.payload).toMatchObject({ modalType: 'CONFIRM_PRIVATE_QUOTE_NOTIFY', modalProps: { overridePrivacy: 'private', onSubmitSuccess: expect.any(Function) } });
  });

  it('skips the missing alt prompt for a direct side-arm submission', () => {
    const state = makeState({ media_attachments: [{ type: 'image', description: '' }] });
    state.meta = state.meta.set('missing_alt_text_modal', true);
    const dispatch = runSubmit(state, { overridePrivacy: 'direct' });
    expect(dispatch.mock.calls.some(([action]) => action.type === 'MODAL_OPEN')).toBe(false);
    expect(mocks.submit).toHaveBeenCalledWith(expect.any(Function), 'direct');
  });

  it('preserves side-arm privacy when asking to publish without a content warning', () => {
    const dispatch = runSubmit(makeState({ spoiler: true }), { overridePrivacy: 'private' });
    const modal = dispatch.mock.calls.find(([action]) => action.type === 'MODAL_OPEN')[0];
    expect(modal.payload).toMatchObject({ modalType: 'COMPOSER_ADD_CONTENT_WARNING', modalProps: { overridePrivacy: 'private' } });
  });

  it('passes the same completion callback through the missing alt text confirmation', () => {
    const state = makeState({ media_attachments: [{ type: 'image', description: '' }] });
    state.meta = state.meta.set('missing_alt_text_modal', true);
    const dispatch = runSubmit(state, { overridePrivacy: 'private' });
    const modal = dispatch.mock.calls.find(([action]) => action.type === 'MODAL_OPEN')[0];
    expect(modal.payload.modalType).toBe('CONFIRM_MISSING_ALT_TEXT');
    expect(modal.payload.modalProps.overridePrivacy).toBe('private');

    modal.payload.modalProps.onSubmitSuccess({ id: 'published', url: '/post' });

    expect(state.composer.displayState).toBe('hidden');
  });
});
