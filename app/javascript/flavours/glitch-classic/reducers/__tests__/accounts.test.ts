import { Map as ImmutableMap, Record } from 'immutable';

import {
  followAccountSuccess,
  unfollowAccountSuccess,
} from '../../actions/accounts_typed';
import type { Account } from '../../models/account';
import { accountDefaultValues } from '../../models/account';
import { createRelationship } from '../../models/relationship';
import { accountsReducer } from '../accounts';

vi.mock('flavours/glitch-classic/initial_state', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  me: 'self',
}));

describe('account counts', () => {
  it('preserves hidden follower counts through follow changes while updating visible counts', () => {
    const account = Record(accountDefaultValues);
    const relationship = createRelationship({ id: 'target' }).toObject();
    for (const count of [-1, 0, 1234]) {
      const state = ImmutableMap<string, Account>({
        target: account({ followers_count: count }),
        self: account({ following_count: Math.max(0, count) }),
      });
      const followed = accountsReducer(
        state,
        followAccountSuccess({
          relationship,
          alreadyFollowing: false,
        }),
      );
      expect(followed.get('target')?.followers_count).toBe(
        count < 0 ? count : count + 1,
      );
      expect(followed.get('self')?.following_count).toBe(
        Math.max(0, count) + 1,
      );
      expect(
        accountsReducer(
          state,
          followAccountSuccess({
            relationship,
            alreadyFollowing: true,
          }),
        ),
      ).toBe(state);

      const unfollowed = accountsReducer(
        state,
        unfollowAccountSuccess({
          relationship,
          statuses: [],
        }),
      );
      expect(unfollowed.get('target')?.followers_count).toBe(
        count < 0 ? count : Math.max(0, count - 1),
      );
      expect(unfollowed.get('self')?.following_count).toBe(
        Math.max(0, count - 1),
      );
    }
  });
});
