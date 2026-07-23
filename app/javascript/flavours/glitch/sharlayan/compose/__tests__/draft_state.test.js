import { fromJS, List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { reduceStatusDraftCompose } from '../draft_state';

describe('reduceStatusDraftCompose', () => {
  const state = ImmutableMap({
    default_language: 'en',
    advanced_options: ImmutableMap({ do_not_federate: false }),
  });

  it('restores the complete compose payload from a server draft', () => {
    const draft = fromJS({
      id: '42',
      params: {
        status: 'Saved text',
        spoiler_text: 'CW',
        content_type: 'text/markdown',
        visibility: 'private',
        local_only: true,
        language: 'ko',
        poll: {
          options: ['One', 'Two'],
          multiple: true,
          expires_in: 3600,
        },
      },
      media_attachments: [{ id: '7', type: 'image' }],
    });

    const result = reduceStatusDraftCompose(state, {
      type: 'COMPOSE_SET_DRAFT',
      draft,
      maxOptions: 4,
    });

    expect(result.get('draft_id')).toBe('42');
    expect(result.get('text')).toBe('Saved text');
    expect(result.get('spoiler_text')).toBe('CW');
    expect(result.get('privacy')).toBe('private');
    expect(result.get('language')).toBe('ko');
    expect(result.getIn(['advanced_options', 'do_not_federate'])).toBe(true);
    expect(result.getIn(['poll', 'options'])).toEqual(ImmutableList(['One', 'Two', '']));
    expect(result.get('media_attachments').first().get('id')).toBe('7');
  });

  it('tracks the ID returned after saving', () => {
    const result = reduceStatusDraftCompose(state, {
      type: 'STATUS_DRAFT_SAVE_SUCCESS',
      draft: fromJS({ id: '99' }),
    });

    expect(result.get('draft_id')).toBe('99');
  });
});
