import assert from 'node:assert';
import { test } from 'node:test';

import { ChatDiceError, DICE_ENGINE, roll } from './chat_dice_worker.js';

const reasonOf = (callback) => {
  try {
    callback();
  } catch (error) {
    return error instanceof ChatDiceError ? error.reason : 'other';
  }
  return null;
};

test('rolls supported notation with the pinned engine metadata', () => {
  const result = roll('2d20kh1');

  assert.deepStrictEqual(Object.keys(result), ['version', 'engine', 'engineVersion', 'notation', 'total', 'output']);
  assert.strictEqual(result.engine, DICE_ENGINE);
  assert.strictEqual(result.engineVersion, '5.5.1');
  assert.strictEqual(result.notation, '2d20kh1');
  assert.ok(result.total >= 1 && result.total <= 20);
  assert.match(result.output, /^2d20kh1: \[/);
});

test('rejects nesting, random draws and notation beyond the limits', () => {
  assert.strictEqual(reasonOf(() => roll(`${'('.repeat(40)}1${')'.repeat(40)}`)), 'limit');
  assert.strictEqual(reasonOf(() => roll(`1d6[${'('.repeat(40)}]`)), null);
  assert.strictEqual(reasonOf(() => roll('999d6+999d6')), 'limit');
  assert.strictEqual(reasonOf(() => roll(`1d6${' '.repeat(600)}`)), 'limit');
  assert.notStrictEqual(reasonOf(() => roll('nope(')), null);
});
