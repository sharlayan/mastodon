import { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { getSharlayanComposeSubmission } from '../submission';

const getState = (compose) => () => ImmutableMap({ compose }).set('compose', compose);

describe('Sharlayan compose submission', () => {
  it('uses circle visibility and prevents automatic quotes for new circle posts', () => {
    const submission = getSharlayanComposeSubmission({
      getState: getState(ImmutableMap({ circle_id: 'circle-id', clip_ids: ImmutableList(['clip-id']), quote_policy: 'public', scheduled_at: '2026-07-18T01:00:00Z' })),
      effectiveStatusId: null,
      overridePrivacy: null,
    });

    expect(submission).toMatchObject({ circleId: 'circle-id', visibility: 'circle', clipIds: ['clip-id'], quoteApprovalPolicy: 'nobody', scheduledAt: '2026-07-18T01:00:00Z' });
  });

  it('normalizes poll options without changing their poll settings', () => {
    const submission = getSharlayanComposeSubmission({
      getState: getState(ImmutableMap({
        circle_id: null,
        clip_ids: ImmutableList(),
        privacy: 'public',
        quote_policy: 'public',
        poll: ImmutableMap({ options: ImmutableList([' First ', '', 2]), expires_in: 3600, multiple: true, hide_totals: true }),
      })),
      effectiveStatusId: null,
      overridePrivacy: null,
    });

    expect(submission.poll).toEqual({ options: ['First', '2'], expires_in: 3600, multiple: true, hide_totals: true });
  });

  it('does not apply new-post extensions when updating an existing status', () => {
    const submission = getSharlayanComposeSubmission({
      getState: getState(ImmutableMap({ circle_id: 'circle-id', clip_ids: ImmutableList(['clip-id']), privacy: 'unlisted', quote_policy: 'public', scheduled_at: '2026-07-18T01:00:00Z' })),
      effectiveStatusId: 'status-id',
      overridePrivacy: null,
    });

    expect(submission).toMatchObject({ circleId: null, visibility: 'unlisted', clipIds: undefined, scheduledAt: undefined, quoteApprovalPolicy: 'public' });
  });
});
