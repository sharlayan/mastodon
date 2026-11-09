import { isRemoteAccount, reactionFromEmoji } from '../index';

import '../testing/match_media';

describe('chat federation helpers', () => {
  it('marks accounts with a domain as remote', () => {
    expect(
      isRemoteAccount({
        id: '1',
        acct: 'bob@remote.test',
        display_name: 'Bob',
        avatar: '',
        avatar_static: '',
      }),
    ).toBe(true);
    expect(
      isRemoteAccount({
        id: '2',
        acct: 'alice',
        display_name: 'Alice',
        avatar: '',
        avatar_static: '',
      }),
    ).toBe(false);
  });

  it('uses the native emoji value for reactions', () => {
    expect(reactionFromEmoji({ native: '🎉', colons: ':tada:' })).toBe('🎉');
    expect(reactionFromEmoji({ colons: ':tada:' })).toBe(':tada:');
    expect(reactionFromEmoji({})).toBeNull();
  });
});
