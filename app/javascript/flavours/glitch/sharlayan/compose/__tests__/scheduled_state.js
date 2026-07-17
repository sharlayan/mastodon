import { List as ImmutableList, Map as ImmutableMap } from 'immutable';
import { composeReducer } from '../../../reducers/compose';

import { reduceScheduledCompose } from '../scheduled_state';

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

  it('is applied by the core compose reducer', () => {
    expect(composeReducer(undefined, {
      type: 'COMPOSE_SCHEDULED_AT_CHANGE',
      scheduledAt: '2026-07-18T01:00:00Z',
    }).get('scheduled_at')).toBe('2026-07-18T01:00:00Z');
  });
});
