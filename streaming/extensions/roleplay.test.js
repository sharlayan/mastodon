import { strict as assert } from 'node:assert';
import test from 'node:test';

import { isRoleplayPublicTimelineChannel } from './roleplay.js';

test('roleplay mode restricts every public timeline channel', () => {
  const env = { OC_ROLEPLAY_OPTION: 'true' };

  assert.equal(isRoleplayPublicTimelineChannel('public', env), true);
  assert.equal(isRoleplayPublicTimelineChannel('public:local', env), true);
  assert.equal(isRoleplayPublicTimelineChannel('public:remote:media', env), true);
  assert.equal(isRoleplayPublicTimelineChannel('user', env), false);
  assert.equal(isRoleplayPublicTimelineChannel('hashtag:local', env), false);
});

test('public timeline channels remain available outside roleplay mode', () => {
  assert.equal(isRoleplayPublicTimelineChannel('public', {}), false);
  assert.equal(
    isRoleplayPublicTimelineChannel('public:local', {
      OC_ROLEPLAY_OPTION: 'false',
    }),
    false,
  );
});
