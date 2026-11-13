import { fromJS } from 'immutable';

import { makeGetConversationRecipientAccounts } from '../selectors';

describe('conversation selectors', () => {
  it('keeps recipient accounts stable while compose state changes', () => {
    const getRecipientAccounts = makeGetConversationRecipientAccounts();
    const recipientIds = ['first', 'missing', 'second'];
    const state = fromJS({
      accounts: {
        first: { id: 'first', username: 'alice' },
        second: { id: 'second', username: 'bob' },
      },
      direct_compose: { conversation: { text: '' } },
    });
    const changedCompose = state.setIn(
      ['direct_compose', 'conversation', 'text'],
      'a',
    );

    expect(getRecipientAccounts(changedCompose, recipientIds)).toBe(
      getRecipientAccounts(state, recipientIds),
    );
    expect(
      getRecipientAccounts(state, recipientIds)
        .map((account) => account.get('username')),
    ).toEqual(['alice', 'bob']);
  });
});
