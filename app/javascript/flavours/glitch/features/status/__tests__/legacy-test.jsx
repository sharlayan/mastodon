import { fromJS } from 'immutable';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { replyComposeById } from '@/flavours/glitch/actions/compose_typed';
import { closeModal } from '@/flavours/glitch/actions/modal';
import { browserHistory } from '@/flavours/glitch/components/router';
import { rootReducer } from '@/flavours/glitch/reducers';
import { accountFactoryAPI, statusFactoryAPI } from '@/testing/factories';

import { Status } from '../legacy';

vi.hoisted(() => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockReturnValue({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    }),
  });
});

const { apiGet, apiRequest } = vi.hoisted(() => ({ apiGet: vi.fn(), apiRequest: vi.fn() }));

vi.mock('@/flavours/glitch/api', async (importOriginal) => ({
  ...(await importOriginal()),
  default: () => ({ get: apiGet, request: apiRequest }),
}));

vi.mock('@/flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal()),
  localStatusPageAccess: 'authenticated',
}));

vi.mock('@/flavours/glitch/is_mobile', async (importOriginal) => ({
  ...(await importOriginal()),
  layoutFromWindow: () => 'single-column',
}));

const createReplyHarness = ({ draft = {}, settings = {}, repliable = true } = {}) => {
  const status = fromJS({
    id: 'reply-status',
    account: 'reply-account',
    mentions: [],
    visibility: 'public',
    spoiler_text: '',
    repliable,
  });
  const account = fromJS({ id: 'reply-account', acct: 'alice' });
  let state = rootReducer(undefined, { type: '@@INIT' })
    .setIn(['statuses', status.get('id')], status)
    .setIn(['accounts', account.get('id')], account)
    .update('compose', compose => compose.merge(fromJS(draft)))
    .update('local_settings', localSettings => localSettings.merge({
      confirm_before_clearing_draft: true,
      inline_compose_timelines: true,
      ...settings,
    }));

  const dispatch = vi.fn(action => {
    if (typeof action === 'function') {
      return action(dispatch, () => state);
    }
    state = rootReducer(state, action);
    return action;
  });
  const component = new Status({ dispatch, identity: { signedIn: true } });

  return { component, dispatch, getState: () => state, status };
};

describe('legacy detailed reply', () => {
  beforeEach(() => {
    browserHistory.replace('/home');
  });

  afterEach(() => {
    browserHistory.replace('/');
  });

  it('keeps content warning, media, poll, quote or pending upload-only drafts until the reply is confirmed', () => {
    const drafts = [
      ['content warning', { spoiler: true, spoiler_text: 'Draft warning' }],
      ['media', { media_attachments: [{ id: 'draft-media', unattached: true }] }],
      ['poll', { poll: { options: ['First', 'Second'] } }],
      ['quote', { quoted_status_id: 'draft-quote' }],
      ['pending upload', { pending_media_attachments: 1 }],
    ];

    expect(drafts.map(([kind, draft]) => {
      const { component, getState, status } = createReplyHarness({ draft });
      const originalCompose = getState().compose;

      component.handleReplyClick(status);

      return [kind, getState().compose === originalCompose, getState().modal.get('stack').first().toJS()];
    })).toEqual(drafts.map(([kind]) => [kind, true, {
      modalType: 'CONFIRM_REPLY',
      modalProps: { statusId: 'reply-status' },
    }]));
  });

  it('opens the custom inline composer after confirming a reply', () => {
    const { component, dispatch, getState, status } = createReplyHarness({
      draft: { spoiler: true, spoiler_text: 'Draft warning' },
    });
    component.handleReplyClick(status);
    dispatch(closeModal({ modalType: 'CONFIRM_REPLY', ignoreFocus: false }));

    dispatch(replyComposeById({ statusId: status.get('id'), force: true }));

    expect(getState().compose.get('in_reply_to')).toBe('reply-status');
    expect(getState().compose.get('text')).toBe('@alice ');
    expect(getState().modal.get('stack').first().get('modalType')).toBe('INLINE_COMPOSE');
    expect(browserHistory.location.pathname).toBe('/home');
  });

  it('respects the disabled draft confirmation setting', () => {
    const { component, getState, status } = createReplyHarness({
      draft: { spoiler: true, spoiler_text: 'Draft warning' },
      settings: { confirm_before_clearing_draft: false },
    });

    component.handleReplyClick(status);

    expect(getState().compose.get('in_reply_to')).toBe('reply-status');
    expect(getState().modal.get('stack').first().get('modalType')).toBe('INLINE_COMPOSE');
  });

  it('does not open the inline modal when inline compose is disabled', () => {
    const { component, getState, status } = createReplyHarness({
      draft: { mounted: 1 },
      settings: { inline_compose_timelines: false },
    });

    component.handleReplyClick(status);

    expect(getState().compose.get('in_reply_to')).toBe('reply-status');
    expect(getState().modal.get('stack').size).toBe(0);
  });

  it('keeps the custom non-repliable status guard', () => {
    const { component, dispatch, status } = createReplyHarness({ repliable: false });

    component.handleReplyClick(status);

    expect(dispatch).not.toHaveBeenCalled();
  });
});

describe('legacy status page for logged-out visitors on a restricted server', () => {
  const loadStatusPage = async (statusId) => {
    let state = rootReducer(undefined, { type: '@@INIT' });
    const dispatch = vi.fn(action => {
      if (typeof action === 'function') {
        return action(dispatch, () => state);
      }
      state = rootReducer(state, action);
      return action;
    });
    const component = new Status({ dispatch, identity: { signedIn: false }, params: { statusId } });
    component.setState = vi.fn(update => Object.assign(component.state, update));

    component._fetchStatus(statusId);
    await vi.waitFor(() => expect(state.getIn(['statuses', statusId, 'isLoading'])).toBeFalsy());

    return { component };
  };

  afterEach(() => {
    apiGet.mockReset();
    apiRequest.mockReset();
  });

  it('loads remote statuses the server allows', async () => {
    apiGet.mockResolvedValue({ data: statusFactoryAPI({ id: 'remote-status', account: accountFactoryAPI({ id: 'remote-account', acct: 'bob@remote.example' }) }) });
    apiRequest.mockResolvedValue({ data: { ancestors: [], descendants: [] }, headers: {} });

    const { component } = await loadStatusPage('remote-status');

    expect(component.state.loginRequiredStatusId).toBeUndefined();
    await vi.waitFor(() => expect(apiRequest).toHaveBeenCalledWith(expect.objectContaining({ url: '/api/v1/statuses/remote-status/context' })));
  });

  it('asks for login only when the API refuses the status', async () => {
    apiGet.mockRejectedValue(Object.assign(new Error('Request failed'), { status: 422, response: { status: 422, data: {} } }));

    const { component } = await loadStatusPage('local-status');

    expect(component.state.loginRequiredStatusId).toBe('local-status');
    expect(apiRequest).not.toHaveBeenCalled();
  });

  it('does not ask for login for missing statuses', async () => {
    apiGet.mockRejectedValue(Object.assign(new Error('Request failed'), { status: 404, response: { status: 404, data: {} } }));

    const { component } = await loadStatusPage('missing-status');

    expect(component.state.loginRequiredStatusId).toBeUndefined();
  });
});
