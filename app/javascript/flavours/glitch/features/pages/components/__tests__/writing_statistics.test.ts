import { describe, expect, it } from 'vitest';

import type { ApiPageWritingStatisticsJSON } from 'flavours/glitch/api_types/pages';

import { buildMonthlyWeeks } from '../writing_statistics';

const day = (
  date: string,
  charactersDelta = 0,
): ApiPageWritingStatisticsJSON['days'][number] => ({
  date,
  characters_delta: charactersDelta,
  activity: 'none',
});

describe('buildMonthlyWeeks', () => {
  it('keeps past zero-value weeks and includes a sixth calendar week', () => {
    expect(
      buildMonthlyWeeks([day('2025-06-09', 12)], '2025-06', '2025-08-03'),
    ).toEqual([
      { number: 1, value: 0 },
      { number: 2, value: 0 },
      { number: 3, value: 12 },
      { number: 4, value: 0 },
      { number: 5, value: 0 },
      { number: 6, value: 0 },
    ]);
  });

  it('omits fifth and sixth weeks when the month only has four', () => {
    expect(buildMonthlyWeeks([], '2021-02', '2025-08-03')).toEqual([
      { number: 1, value: 0 },
      { number: 2, value: 0 },
      { number: 3, value: 0 },
      { number: 4, value: 0 },
    ]);
  });

  it('omits future weeks from the current month', () => {
    expect(
      buildMonthlyWeeks([day('2025-06-10', 5)], '2025-06', '2025-06-10'),
    ).toEqual([
      { number: 1, value: 0 },
      { number: 2, value: 0 },
      { number: 3, value: 5 },
    ]);
  });
});
