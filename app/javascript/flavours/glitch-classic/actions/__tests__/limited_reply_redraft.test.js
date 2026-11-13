import { fromJS } from 'immutable';

import api from '../../api';
import { deleteStatus, REDRAFT } from '../statuses';

vi.mock('../../api', () => ({ default: vi.fn() }));
vi.mock('flavours/glitch-classic/components/router', () => ({ browserHistory: {} }));
vi.mock('../compose', () => ({ ensureComposeIsVisible: vi.fn(), setComposeToStatus: vi.fn() }));
vi.mock('../importer', () => ({ importFetchedAccount: () => ({ type: 'IMPORT_ACCOUNT' }) }));
vi.mock('../timelines', () => ({ deleteFromTimelines: () => ({ type: 'DELETE_FROM_TIMELINES' }) }));
vi.mock('../statuses_typed', () => ({ fetchContext: vi.fn() }));

it('passes the authoritative reply or circle source audience to redraft while retaining the normalized poll', async () => {
  for (const source of [
    { limited_scope: 'reply', limited_reply_account_ids: ['author', 'hidden'] },
    { limited_scope: 'circle', circle_id: 'circle' },
  ]) {
    const data = fromJS({ statuses: { posted: { id: 'posted', in_reply_to_id: 'parent', visibility: 'private', poll: 'poll' } }, polls: { poll: { id: 'poll', options: [{ title: 'Yes' }, { title: 'No' }] } } });
    const state = { getIn: path => data.getIn(path), server: { server: { item: { configuration: { polls: { max_options: 4 } } } } } };
    const apiDelete = vi.fn().mockResolvedValue({ data: { text: 'Source text', content_type: 'text/plain', account: { id: 'self' }, ...source } });
    vi.mocked(api).mockReturnValue({ delete: apiDelete });
    const actions = [];
    const dispatch = action => typeof action === 'function' ? action(dispatch, () => state) : actions.push(action);

    await dispatch(deleteStatus('posted', true));
    const restored = actions.find(action => action.type === REDRAFT);
    expect(restored.status.get('limited_scope')).toBe(source.limited_scope);
    expect(restored.status.get('limited_reply_account_ids')?.toArray()).toEqual(source.limited_reply_account_ids);
    expect(restored.status.get('circle_id')).toBe(source.circle_id);
    expect(restored.status.get('poll')).toEqual(data.getIn(['polls', 'poll']));
    expect(restored.raw_text).toBe('Source text');
  }
});
