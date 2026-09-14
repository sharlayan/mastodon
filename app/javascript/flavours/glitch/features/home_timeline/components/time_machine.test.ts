import { isTimeMachineTimestampValid } from './time_machine';

describe('isTimeMachineTimestampValid', () => {
  const now = new Date('2026-09-14T12:34:56.789Z');

  test('accepts a timestamp exactly seven days ago', () => {
    expect(
      isTimeMachineTimestampValid(new Date('2026-09-07T12:34:56.789Z'), now),
    ).toBe(true);
  });

  test('rejects timestamps outside the 168-hour window', () => {
    expect(
      isTimeMachineTimestampValid(new Date('2026-09-07T12:34:56.788Z'), now),
    ).toBe(false);
    expect(
      isTimeMachineTimestampValid(new Date('2026-09-14T12:34:56.790Z'), now),
    ).toBe(false);
  });
});
