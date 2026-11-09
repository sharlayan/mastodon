import { fromJS } from 'immutable';

import { COMPOSE_REPLY, COMPOSE_RESET, COMPOSE_SET_STATUS, COMPOSE_SUBMIT_SUCCESS } from '../../actions/compose';
import { STATUS_DRAFT_DELETE_SUCCESS } from '../../actions/status_drafts';
import { REDRAFT } from '../../actions/statuses';
import { getScheduledSubmissionContext } from '../../sharlayan/compose/scheduled_submission';
import { getSharlayanComposeSubmission } from '../../sharlayan/compose/submission';
import { composeReducer } from '../compose';

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
});
