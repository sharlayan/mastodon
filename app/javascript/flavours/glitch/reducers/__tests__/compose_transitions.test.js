import { fromJS } from 'immutable';

import { COMPOSE_SET_STATUS } from '../../actions/compose';
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

  it.each([COMPOSE_SET_STATUS, REDRAFT])('does not carry over quote and reaction restrictions absent from the source with %s', type => {
    const state = restore(loadedDraft(), type, sourceStatus
      .delete('quote')
      .delete('quote_approval')
      .delete('reaction_acceptance'));

    expect(state.get('quoted_status_id')).toBeNull();
    expect(state.get('quote_policy')).toBe('nobody');
    expect(state.get('reaction_acceptance')).toBeNull();
  });
});
