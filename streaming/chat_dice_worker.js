import { randomBytes } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { DiceRoll, NumberGenerator } from '@dice-roller/rpg-dice-roller';

export const DICE_ENGINE = '@dice-roller/rpg-dice-roller';
export const DICE_ENGINE_VERSION = '5.5.1';
export const DICE_MAX_NOTATION_BYTES = 512;
export const DICE_MAX_OUTPUT_BYTES = 12288;
export const DICE_MAX_RANDOM_DRAWS = 1024;
const DICE_MAX_DEPTH = 32;

export class ChatDiceError extends Error {
  constructor(reason) {
    super(`dice ${reason}`);
    this.reason = reason;
  }
}

export function assertNotation(notation) {
  if (Buffer.byteLength(notation) > DICE_MAX_NOTATION_BYTES)
    throw new ChatDiceError('limit');

  const expression = notation.replace(
    /\/\*[\s\S]*?\*\/|\[[^\]]*\]|(?:\/\/|#)[^\n\r\u2028\u2029]*/g,
    '',
  );
  let depth = 0;
  for (const character of expression) {
    if ('({'.includes(character)) depth++;
    if (')}'.includes(character)) depth = Math.max(0, depth - 1);
    if (depth > DICE_MAX_DEPTH) throw new ChatDiceError('limit');
  }
}

export function roll(notation) {
  let draws = 0;
  NumberGenerator.generator.engine = {
    next() {
      if (++draws > DICE_MAX_RANDOM_DRAWS) throw new ChatDiceError('limit');
      try {
        return randomBytes(4).readInt32LE(0);
      } catch {
        throw new ChatDiceError('busy');
      }
    },
  };

  assertNotation(notation);
  let diceRoll;
  try {
    diceRoll = new DiceRoll(notation);
  } catch (error) {
    if (draws > DICE_MAX_RANDOM_DRAWS) throw new ChatDiceError('limit');
    throw error;
  }
  const result = {
    version: 1,
    engine: DICE_ENGINE,
    engineVersion: DICE_ENGINE_VERSION,
    notation: diceRoll.notation,
    total: diceRoll.total,
    output: diceRoll.output,
  };

  if (
    typeof result.total !== 'number' ||
    !Number.isFinite(result.total) ||
    Math.abs(result.total) > Number.MAX_SAFE_INTEGER ||
    typeof result.output !== 'string' ||
    result.output.length === 0 ||
    Buffer.byteLength(result.output) > DICE_MAX_OUTPUT_BYTES
  )
    throw new ChatDiceError('limit');

  return result;
}

const reasonOf = (error) =>
  error instanceof ChatDiceError ? error.reason : 'invalid';

const readInput = async () => {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
};

const main = async () => {
  let reply;
  try {
    reply = { result: roll(await readInput()) };
  } catch (error) {
    reply = { error: reasonOf(error) };
  }
  process.stdout.write(JSON.stringify(reply));
};

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url))
  await main();
