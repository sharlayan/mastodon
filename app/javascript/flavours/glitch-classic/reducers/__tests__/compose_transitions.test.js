import { fromJS } from 'immutable';

import { COMPOSE_DIRECT, COMPOSE_REPLY, COMPOSE_RESET, COMPOSE_SET_STATUS, COMPOSE_SUBMIT_SUCCESS } from '../../actions/compose';
import { changeComposeCircle, changeComposeVisibility } from '../../actions/compose_typed';
import { STATUS_DRAFT_DELETE_SUCCESS, STATUS_DRAFT_SAVE_REQUEST, STATUS_DRAFT_SAVE_SUCCESS } from '../../actions/status_drafts';
import { REDRAFT } from '../../actions/statuses';
import { timelineDelete } from '../../actions/timelines_typed';
import { getScheduledSubmissionContext } from '../../sharlayan/compose/scheduled_submission';
import { getSharlayanComposeSubmission } from '../../sharlayan/compose/submission';
import { composeReducer } from '../compose';

vi.mock('../../initial_state', async (importOriginal) => ({
  ...(await importOriginal()),
  circlesEnabled: true,
}));

const sourceStatus = fromJS({
  id: 'published-status',
  in_reply_to_id: 'parent-status',
  visibility: 'unlisted',
  sensitive: false,
  spoiler_text: '',
  language: 'ko',
  local_only: true,
  media_attachments: [],
  quote: { quoted_status: 'source-quote' },
  quote_approval: { automatic: ['followers'] },
  reaction_acceptance: 'nonSensitiveOnly',
  poll: null,
});

const loadedDraft = () => composeReducer(undefined, {
  type: 'COMPOSE_SET_DRAFT',
  draft: fromJS({
    id: 'unrelated-draft',
    params: {
      status: 'A different saved draft',
      scheduled_at: '2030-12-01T12:00:00Z',
      circle_id: 'old-circle',
      clip_ids: ['old-clip'],
      quoted_status_id: 'old-quote',
      reaction_acceptance: 'likeOnly',
      poll: { options: ['Old first', 'Old second'] },
    },
  }),
});

const restore = (state, type, status = sourceStatus) => composeReducer(state, {
  type,
  status,
  text: 'Source text',
  raw_text: 'Source text',
  spoiler_text: '',
  content_type: 'text/x-mfm',
  quoted_status_id: status.getIn(['quote', 'quoted_status'], null),
  maxOptions: 4,
});

describe('compose restoration transitions', () => {
  it.each([COMPOSE_SET_STATUS, REDRAFT])('clears an unrelated draft and schedule when restoring a status with %s', type => {
    const state = restore(loadedDraft(), type);

    expect(state.get('draft_id')).toBeNull();
    expect(state.get('scheduled_at')).toBeNull();
    expect(state.get('circle_id')).toBeNull();
    expect(state.get('clip_ids').isEmpty()).toBe(true);
    expect(state.get('poll')).toBeNull();
    expect(state.get('text')).toBe('Source text');
    expect(state.get('privacy')).toBe('unlisted');
    expect(state.get('in_reply_to')).toBe('parent-status');
    expect(state.get('quoted_status_id')).toBe('source-quote');
    expect(state.get('quote_policy')).toBe('followers');
    expect(state.get('reaction_acceptance')).toBe('nonSensitiveOnly');
    expect(state.get('content_type')).toBe('text/x-mfm');
    expect(state.getIn(['advanced_options', 'do_not_federate'])).toBe(true);

    const context = getScheduledSubmissionContext({
      statusId: state.get('id'),
      scheduledAt: state.get('scheduled_at'),
    });
    expect(context).toEqual({
      editingScheduledId: null,
      effectiveStatusId: type === COMPOSE_SET_STATUS ? 'published-status' : null,
    });
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: context.effectiveStatusId,
    });
    expect(submission.circleId).toBeNull();
    expect(submission.visibility).toBe('unlisted');
    expect(submission.clipIds).toEqual(type === COMPOSE_SET_STATUS ? undefined : []);
  });

  it('does not carry over quote and reaction restrictions absent from the source when editing or redrafting', () => {
    const source = sourceStatus
      .delete('quote')
      .delete('quote_approval')
      .delete('reaction_acceptance');

    expect([COMPOSE_SET_STATUS, REDRAFT].map(type => {
      const state = restore(loadedDraft(), type, source);

      return [type, state.get('quoted_status_id'), state.get('quote_policy'), state.get('reaction_acceptance')];
    })).toEqual([
      [COMPOSE_SET_STATUS, null, 'nobody', null],
      [REDRAFT, null, 'nobody', null],
    ]);
  });

  it('clears a restored circle when starting a direct message', () => {
    const state = composeReducer(loadedDraft(), {
      type: COMPOSE_DIRECT,
      account: fromJS({ id: 'recipient', acct: 'alice' }),
    });
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: null,
    });

    expect(state.get('circle_id')).toBeNull();
    expect(state.get('privacy')).toBe('direct');
    expect(submission).toMatchObject({ circleId: null, visibility: 'direct', quoteApprovalPolicy: 'nobody' });
  });

  it('clears a previously selected circle when replying to a direct message', () => {
    const state = composeReducer(loadedDraft(), {
      type: COMPOSE_REPLY,
      status: sourceStatus.merge(fromJS({ visibility: 'direct', account: { id: 'recipient', acct: 'alice' }, mentions: [] })),
    });
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: null,
    });

    expect(state.get('in_reply_to')).toBe(sourceStatus.get('id'));
    expect(state.get('circle_id')).toBeNull();
    expect(submission).toMatchObject({ circleId: null, visibility: 'direct' });
  });

  it('replaces a previously selected circle with the original limited reply audience', () => {
    const state = composeReducer(loadedDraft(), {
      type: COMPOSE_REPLY,
      status: sourceStatus.merge(fromJS({ visibility: 'private', limited_scope: 'circle', account: { id: 'recipient', acct: 'alice' }, mentions: [] })),
    });
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: null,
    });

    expect(state.get('limited_scope')).toBe('reply');
    expect(submission).toMatchObject({ circleId: null, visibility: 'private', limitedScope: 'reply' });
  });

  it('selects the circle of the own circle post being replied to', () => {
    const state = composeReducer(loadedDraft(), {
      type: COMPOSE_REPLY,
      status: sourceStatus.merge(fromJS({ visibility: 'private', limited_scope: 'personal', circle: { id: 'source-circle', title: 'Friends' }, account: { id: 'me', acct: 'me' }, mentions: [] })),
    });
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: null,
    });

    expect(state.get('circle_id')).toBe('source-circle');
    expect(state.get('limited_scope')).toBeNull();
    expect(state.get('reply_to_limited')).toBe(true);
    expect(submission).toMatchObject({ circleId: 'source-circle', visibility: 'private', limitedScope: undefined });
  });

  it('keeps the circle when continuing a circle thread', () => {
    const threaded = composeReducer(undefined, changeComposeCircle('source-circle')).setIn(['advanced_options', 'threaded_mode'], true);
    const state = composeReducer(threaded, { type: COMPOSE_SUBMIT_SUCCESS, status: { id: 'posted', visibility: 'private', limited_scope: 'circle', circle: { id: 'source-circle', title: 'Friends' }, spoiler_text: '', content: '', mentions: [], tags: [], account: { id: 'me', acct: 'me' } } });

    expect(state.get('in_reply_to')).toBe('posted');
    expect(state.get('circle_id')).toBe('source-circle');
    expect(state.get('limited_scope')).toBeNull();
  });

  it('allows a circle to be explicitly selected after entering direct mode', () => {
    const direct = composeReducer(undefined, { type: COMPOSE_DIRECT, account: fromJS({ id: 'recipient', acct: 'alice' }) });
    const state = composeReducer(direct, changeComposeCircle('chosen-circle'));
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: null,
    });

    expect(state.get('privacy')).toBe('private');
    expect(submission).toMatchObject({ circleId: 'chosen-circle', visibility: 'private' });
  });

  it('keeps direct visibility when a stale circle reaches the submission boundary', () => {
    const state = loadedDraft().set('privacy', 'direct');
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: null,
    });

    expect(submission).toMatchObject({ circleId: null, visibility: 'direct', quoteApprovalPolicy: 'nobody' });
  });

  it('forgets the loaded draft when the composer is reset', () => {
    expect(composeReducer(loadedDraft(), { type: COMPOSE_RESET }).get('draft_id')).toBeNull();
  });

  it('forgets the loaded draft when replying to another status', () => {
    const state = composeReducer(loadedDraft(), { type: COMPOSE_REPLY, status: sourceStatus.merge(fromJS({ account: { id: '1', acct: 'alice' }, mentions: [] })) });

    expect(state.get('draft_id')).toBeNull();
  });

  it('forgets the loaded draft after the first post of a thread', () => {
    const threaded = loadedDraft().setIn(['advanced_options', 'threaded_mode'], true);
    const state = composeReducer(threaded, { type: COMPOSE_SUBMIT_SUCCESS, status: { id: 'posted', visibility: 'public', spoiler_text: '', content: '', mentions: [], tags: [], account: { id: '1', acct: 'me' } } });

    expect(state.get('in_reply_to')).toBe('posted');
    expect(state.get('draft_id')).toBeNull();
  });

  it.each([
    ['reset', { type: COMPOSE_RESET }],
    ['submitted', { type: COMPOSE_SUBMIT_SUCCESS, status: { id: 'posted', visibility: 'public' } }],
  ])('ignores a draft save that finishes after the composer was %s', (_label, action) => {
    const saving = composeReducer(undefined, { type: STATUS_DRAFT_SAVE_REQUEST, requestId: 'save-1' });
    const state = composeReducer(composeReducer(saving, action), { type: STATUS_DRAFT_SAVE_SUCCESS, draft: fromJS({ id: 'late-draft' }), requestId: 'save-1' });

    expect(state.get('draft_id')).toBeNull();
    expect(state.get('draft_save_request')).toBeNull();
  });

  it('tracks the draft from a save that finishes while the composer is unchanged', () => {
    const saving = composeReducer(undefined, { type: STATUS_DRAFT_SAVE_REQUEST, requestId: 'save-1' });
    const state = composeReducer(saving, { type: STATUS_DRAFT_SAVE_SUCCESS, draft: fromJS({ id: 'saved-draft' }), requestId: 'save-1' });

    expect(saving.get('draft_save_request')).toBe('save-1');
    expect(state.get('draft_id')).toBe('saved-draft');
    expect(state.get('draft_save_request')).toBeNull();
  });

  it('narrows a reply scope when the server saves its draft without the unavailable parent', () => {
    const replying = restore(loadedDraft(), REDRAFT, sourceStatus.merge(fromJS({ visibility: 'private', limited_scope: 'reply', limited_reply_account_ids: ['recipient'] })));
    const saving = composeReducer(replying, { type: STATUS_DRAFT_SAVE_REQUEST, requestId: 'save-1' });
    const save = params => composeReducer(saving, { type: STATUS_DRAFT_SAVE_SUCCESS, draft: fromJS({ id: 'saved-draft', params }), requestId: 'save-1' });
    const narrowed = save({ status: 'A reply', visibility: 'direct' });

    expect(save({ status: 'A reply', visibility: 'private', limited_scope: 'reply', in_reply_to_id: 'parent-status', limited_reply_account_ids: ['recipient'] }).get('limited_scope')).toBe('reply');
    expect(narrowed.get('in_reply_to')).toBeNull();
    expect(narrowed.get('limited_scope')).toBeNull();
    expect(narrowed.get('limited_reply_account_ids')).toBeNull();
    expect(getSharlayanComposeSubmission({ getState: () => fromJS({}).set('compose', narrowed), effectiveStatusId: null })).toMatchObject({ visibility: 'direct', limitedScope: undefined });
  });

  it('forgets the loaded draft only when that draft is deleted', () => {
    expect(composeReducer(loadedDraft(), { type: STATUS_DRAFT_DELETE_SUCCESS, id: 'other-draft' }).get('draft_id')).toBe('unrelated-draft');
    expect(composeReducer(loadedDraft(), { type: STATUS_DRAFT_DELETE_SUCCESS, id: 'unrelated-draft' }).get('draft_id')).toBeNull();
  });

  it('restores the circle of a redrafted circle post', () => {
    const state = restore(loadedDraft(), REDRAFT, sourceStatus.merge({ visibility: 'private', limited_scope: 'circle', circle_id: 'source-circle' }));
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: null,
    });

    expect(submission.circleId).toBe('source-circle');
    expect(submission.visibility).toBe('private');
  });

  it('narrows a redrafted limited post without a known circle to direct', () => {
    const state = restore(loadedDraft(), REDRAFT, sourceStatus.merge({ visibility: 'private', limited_scope: 'reply' }));
    const submission = getSharlayanComposeSubmission({
      getState: () => fromJS({}).set('compose', state),
      effectiveStatusId: null,
    });

    expect(submission.circleId).toBeNull();
    expect(submission.visibility).toBe('direct');
  });

  it('preserves the recipient snapshot through redraft, draft and scheduled restoration', () => {
    const audience = ['parent-author', 'hidden-recipient'];
    const original = sourceStatus.merge(fromJS({ visibility: 'private', limited_scope: 'reply', limited_reply_account_ids: audience }));
    const redrafted = restore(loadedDraft(), REDRAFT, original);
    const params = { visibility: 'private', limited_scope: 'reply', limited_reply_account_ids: audience, in_reply_to_id: 'parent-status' };
    const states = [
      redrafted,
      composeReducer(undefined, { type: 'COMPOSE_SET_DRAFT', draft: fromJS({ id: 'reply-draft', params }) }),
      composeReducer(undefined, { type: 'COMPOSE_SET_SCHEDULED', scheduledStatus: fromJS({ id: 'reply-schedule', scheduled_at: '2030-12-01T12:00:00Z', params }) }),
    ];

    for (const state of states) {
      const submit = (overridePrivacy) => getSharlayanComposeSubmission({ getState: () => fromJS({}).set('compose', state), effectiveStatusId: null, overridePrivacy });
      expect(state.get('reply_to_limited')).toBe(true);
      expect(submit()).toMatchObject({ visibility: 'private', limitedScope: 'reply', limitedReplyAccountIds: audience, circleId: null });
      expect(submit('public')).toMatchObject({ visibility: 'private', limitedScope: 'reply', limitedReplyAccountIds: audience });
      expect(submit('direct')).toMatchObject({ visibility: 'direct', limitedScope: undefined, limitedReplyAccountIds: undefined });
    }
  });

  it('clears reply scope on an explicit privacy change and restores it only for an eligible reply', () => {
    const initial = composeReducer(undefined, {
      type: COMPOSE_REPLY,
      status: sourceStatus.merge(fromJS({ visibility: 'private', limited_scope: 'circle', account: { id: 'recipient', acct: 'alice' }, mentions: [] })),
    });
    const followers = composeReducer(initial, { type: changeComposeVisibility.type, payload: 'private' });
    const restored = composeReducer(followers, { type: 'compose/reply_scope_change', payload: true });

    expect(initial.get('limited_scope')).toBe('reply');
    expect(followers.get('limited_scope')).toBeNull();
    expect(restored.get('limited_scope')).toBe('reply');
    expect(composeReducer(restored, changeComposeCircle(null)).get('limited_scope')).toBe('reply');
    expect(composeReducer(restored, changeComposeCircle('chosen-circle')).get('limited_scope')).toBeNull();
    expect(composeReducer(restored, { type: COMPOSE_RESET }).get('limited_scope')).toBeNull();
    expect(composeReducer(undefined, { type: 'compose/reply_scope_change', payload: true }).get('limited_scope')).toBeNull();
  });


  it('narrows a reply scope to direct but keeps a selected circle when the parent is deleted', () => {
    const state = restore(loadedDraft(), REDRAFT, sourceStatus.merge(fromJS({ visibility: 'private', limited_scope: 'reply', limited_reply_account_ids: ['recipient'] })));
    const deleted = composeReducer(state, timelineDelete({ statusId: 'parent-status' }));
    const submission = getSharlayanComposeSubmission({ getState: () => fromJS({}).set('compose', deleted), effectiveStatusId: null });

    expect(deleted.get('in_reply_to')).toBeNull();
    expect(deleted.get('reply_to_limited')).toBe(false);
    expect(deleted.get('limited_scope')).toBeNull();
    expect(deleted.get('limited_reply_account_ids')).toBeNull();
    expect(deleted.get('circle_id')).toBeNull();
    expect(submission).toMatchObject({ visibility: 'direct', limitedScope: undefined, circleId: null });

    const circleReply = composeReducer(
      composeReducer(undefined, { type: COMPOSE_REPLY, status: sourceStatus.merge(fromJS({ id: 'public-parent', visibility: 'public', account: { id: 'recipient', acct: 'alice' }, mentions: [] })) }),
      changeComposeCircle('chosen-circle'),
    );
    const circleDeleted = composeReducer(circleReply, timelineDelete({ statusId: 'public-parent' }));
    const circleSubmission = getSharlayanComposeSubmission({ getState: () => fromJS({}).set('compose', circleDeleted), effectiveStatusId: null });

    expect(circleDeleted.get('in_reply_to')).toBeNull();
    expect(circleDeleted.get('circle_id')).toBe('chosen-circle');
    expect(circleSubmission).toMatchObject({ visibility: 'private', circleId: 'chosen-circle' });
  });

});
