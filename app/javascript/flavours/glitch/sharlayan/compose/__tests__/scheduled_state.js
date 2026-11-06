import { fromJS, List as ImmutableList, Map as ImmutableMap } from 'immutable';
import { composeReducer } from '../../../reducers/compose';

import { reduceScheduledCompose } from '../scheduled_state';

vi.mock('flavours/glitch/initial_state', async importOriginal => ({
  ...await importOriginal(),
  defaultContentType: 'text/x-mfm',
}));

const initialState = ImmutableMap({
  advanced_options: ImmutableMap({ do_not_federate: false }),
  default_language: 'en',
  media_attachments: ImmutableList(),
});

describe('scheduled compose state', () => {
  it('loads a scheduled post with its compose-specific state', () => {
    const state = reduceScheduledCompose(initialState, {
      type: 'COMPOSE_SET_SCHEDULED',
      maxOptions: 4,
      scheduledStatus: ImmutableMap({
        id: 'scheduled-id',
        scheduled_at: '2026-07-18T01:00:00Z',
        params: ImmutableMap({
          status: 'Scheduled text',
          spoiler_text: 'CW',
          visibility: 'private',
          language: 'ko',
          local_only: true,
          poll: { options: ['First', 'Second'], multiple: true, expires_in: 3600 },
        }),
        media_attachments: ImmutableList([ImmutableMap({ id: 'media-id' })]),
      }),
    });

    expect(state.get('id')).toBe('scheduled-id');
    expect(state.get('scheduled_at')).toBe('2026-07-18T01:00:00Z');
    expect(state.get('spoiler')).toBe(true);
    expect(state.get('spoiler_text')).toBe('CW');
    expect(state.getIn(['advanced_options', 'do_not_federate'])).toBe(true);
    expect(state.getIn(['media_attachments', 0, 'unattached'])).toBe(true);
    expect(state.getIn(['poll', 'options']).toArray()).toEqual(['First', 'Second', '']);
  });

  it('updates the requested schedule time without handling other actions', () => {
    expect(reduceScheduledCompose(initialState, {
      type: 'COMPOSE_SCHEDULED_AT_CHANGE',
      scheduledAt: '2026-07-18T01:00:00Z',
    }).get('scheduled_at')).toBe('2026-07-18T01:00:00Z');
    expect(reduceScheduledCompose(initialState, { type: 'COMPOSE_CHANGE' })).toBeNull();
  });

  it('restores scheduled reply, quote, audience, format, and reaction settings', () => {
    const state = reduceScheduledCompose(initialState, {
      type: 'COMPOSE_SET_SCHEDULED',
      scheduledStatus: fromJS({
        id: 'scheduled-id',
        scheduled_at: '2026-07-18T01:00:00Z',
        params: {
          status: 'Scheduled text',
          in_reply_to_id: 'reply-id',
          quoted_status_id: 'quote-id',
          quote_approval_policy: 'followers',
          circle_id: 'circle-id',
          clip_ids: ['clip-id'],
          visibility: 'private',
          content_type: 'text/markdown',
          reaction_acceptance: 'nonSensitiveOnly',
          poll: { options: ['First', 'Second'], hide_totals: true },
        },
      }),
    });

    expect(state.get('in_reply_to')).toBe('reply-id');
    expect(state.get('quoted_status_id')).toBe('quote-id');
    expect(state.get('quote_policy')).toBe('followers');
    expect(state.get('circle_id')).toBe('circle-id');
    expect(state.get('clip_ids').toArray()).toEqual(['clip-id']);
    expect(state.get('content_type')).toBe('text/markdown');
    expect(state.get('reaction_acceptance')).toBe('nonSensitiveOnly');
    expect(state.getIn(['poll', 'hide_totals'])).toBe(true);
  });

  it('clears an unrelated draft and stale post settings when opening a scheduled post', () => {
    const previous = initialState.merge(fromJS({
      draft_id: 'unrelated-draft',
      circle_id: 'old-circle',
      clip_ids: ['old-clip'],
      quoted_status_id: 'old-quote',
      quote_policy: 'public',
      content_type: 'text/markdown',
      reaction_acceptance: 'none',
      default_reaction_acceptance: 'likeOnly',
      media_attachments: [{ id: 'old-media' }],
    }));
    const state = reduceScheduledCompose(previous, {
      type: 'COMPOSE_SET_SCHEDULED',
      scheduledStatus: fromJS({ id: 'scheduled-id', params: { text: 'A different post' } }),
    });

    expect(state.get('draft_id')).toBeNull();
    expect(state.get('circle_id')).toBeNull();
    expect(state.get('clip_ids').isEmpty()).toBe(true);
    expect(state.get('quoted_status_id')).toBeNull();
    expect(state.get('quote_policy')).toBe('nobody');
    expect(state.get('content_type')).toBe('text/x-mfm');
    expect(state.get('reaction_acceptance')).toBe('likeOnly');
    expect(state.get('media_attachments').isEmpty()).toBe(true);
  });

  it('clears scheduled settings when discarding the post to start a regular composition', () => {
    const scheduled = composeReducer(undefined, {
      type: 'COMPOSE_SET_SCHEDULED',
      scheduledStatus: fromJS({
        id: 'scheduled-id',
        scheduled_at: '2026-07-18T01:00:00Z',
        params: {
          status: 'Scheduled text',
          content_type: 'text/markdown',
          circle_id: 'circle-id',
          clip_ids: ['clip-id'],
          reaction_acceptance: 'none',
        },
      }),
    });
    const state = composeReducer(scheduled, { type: 'COMPOSE_DISCARD' });

    expect(state.get('id')).toBeNull();
    expect(state.get('scheduled_at')).toBeNull();
    expect(state.get('draft_id')).toBeNull();
    expect(state.get('circle_id')).toBeNull();
    expect(state.get('clip_ids').isEmpty()).toBe(true);
    expect(state.get('reaction_acceptance')).toBe(state.get('default_reaction_acceptance'));
    expect(state.get('content_type')).toBe('text/x-mfm');
  });

  it('preserves explicit acceptance of all reactions instead of applying the current user default', () => {
    const state = reduceScheduledCompose(initialState.set('default_reaction_acceptance', 'likeOnly'), {
      type: 'COMPOSE_SET_SCHEDULED',
      scheduledStatus: fromJS({
        id: 'scheduled-id',
        params: { reaction_acceptance: null },
      }),
    });

    expect(state.get('reaction_acceptance')).toBeNull();
  });

  it('releases a deleted reservation so a failed replacement can be retried as a new post', () => {
    const scheduled = reduceScheduledCompose(initialState, {
      type: 'COMPOSE_SET_SCHEDULED',
      scheduledStatus: fromJS({
        id: 'scheduled-id',
        scheduled_at: '2030-12-01T12:00:00Z',
        params: { text: 'Keep this replacement' },
      }),
    });
    const state = composeReducer(scheduled, {
      type: 'SCHEDULED_STATUS_DELETE_SUCCESS',
      id: 'scheduled-id',
    });
    const failed = composeReducer(state, { type: 'COMPOSE_SUBMIT_FAIL' });

    expect(failed.get('id')).toBeNull();
    expect(failed.get('scheduled_at')).toBe('2030-12-01T12:00:00Z');
    expect(failed.get('text')).toBe('Keep this replacement');
  });

  it('keeps the current composition when another reservation is deleted', () => {
    const state = initialState.merge({ id: 'scheduled-id', scheduled_at: '2030-12-01T12:00:00Z' });

    expect(composeReducer(state, {
      type: 'SCHEDULED_STATUS_DELETE_SUCCESS',
      id: 'different-id',
    })).toBe(state);
  });

  it('does not clear an ordinary status edit when an unrelated reservation has the same ID', () => {
    const state = initialState.merge({ id: 'status-id', scheduled_at: null });

    expect(composeReducer(state, {
      type: 'SCHEDULED_STATUS_DELETE_SUCCESS',
      id: 'status-id',
    })).toBe(state);
  });

  it('is applied by the core compose reducer', () => {
    expect(composeReducer(undefined, {
      type: 'COMPOSE_SCHEDULED_AT_CHANGE',
      scheduledAt: '2026-07-18T01:00:00Z',
    }).get('scheduled_at')).toBe('2026-07-18T01:00:00Z');
  });
});
