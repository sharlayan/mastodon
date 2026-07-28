import assert from 'node:assert';
import { test } from 'node:test';

import { filterPayload, mutedNoteUpdate } from './custom_emoji_filter.js';

const rules = [
  { prefix: 'mute', domain: '' },
  { prefix: 'remote', domain: 'example.com' },
];

test('replaces muted custom emoji text and removes REST metadata and reactions', () => {
  const payload = {
    content: '<p>:muted_face: :visible:</p>',
    emojis: [
      { shortcode: 'muted_face', url: 'https://local/muted.gif' },
      { shortcode: 'visible', url: 'https://local/visible.gif' },
    ],
    reactions: [
      { name: 'muted_reaction', domain: '', url: 'https://local/muted.gif' },
      { name: 'visible', domain: '', url: 'https://local/visible.gif' },
    ],
  };

  filterPayload(payload, rules);

  assert.equal(payload.content, '<p>⬛ :visible:</p>');
  assert.deepEqual(payload.emojis.map((emoji) => emoji.shortcode), ['visible']);
  assert.deepEqual(payload.reactions.map((reaction) => reaction.name), ['visible']);
});

test('filters Misskey emoji and reaction maps', () => {
  const payload = {
    text: ':remote_face:',
    emojis: {
      'remote_face@example.com': 'https://example.com/muted.gif',
      'remote_face@elsewhere.example': 'https://elsewhere.example/visible.gif',
    },
    reactions: {
      ':muted_reaction@.:': 2,
      ':visible@.:': 1,
    },
    reactionEmojis: {
      'muted_reaction@.': 'https://local/muted.gif',
      'visible@.': 'https://local/visible.gif',
    },
  };

  filterPayload(payload, rules);

  assert.equal(payload.text, '⬛');
  assert.deepEqual(Object.keys(payload.emojis), ['remote_face@elsewhere.example']);
  assert.deepEqual(Object.keys(payload.reactions), [':visible@.:']);
  assert.deepEqual(Object.keys(payload.reactionEmojis), ['visible@.']);
});

test('drops muted reaction notifications and Misskey reaction updates', () => {
  const payload = [
    { type: 'reaction', reaction: { name: 'muted_reaction', domain: '', url: 'muted-url' } },
    { type: 'mention' },
  ];

  filterPayload(payload, rules);

  assert.deepEqual(payload, [{ type: 'mention' }]);
  assert.equal(mutedNoteUpdate('noteUpdated', { body: { reaction: ':muted_reaction@.:' } }, rules), true);
});
