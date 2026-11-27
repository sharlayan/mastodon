import {
  getComposeControlState,
  shouldShowScheduleButton,
} from './calculations';

describe('Sharlayan compose calculations', () => {
  it('keeps the schedule control visible while editing a scheduled post', () => {
    expect(shouldShowScheduleButton(false, true)).toBe(true);
    expect(shouldShowScheduleButton(false, false)).toBe(false);
  });

  it('preserves compose control state for new, scheduled and edited posts', () => {
    const cases: [
      Parameters<typeof getComposeControlState>[0],
      ReturnType<typeof getComposeControlState>,
    ][] = [
      [
        {},
        {
          scheduleDisabled: false,
          scheduleEditing: false,
          scheduleVisible: false,
          selectionDisabled: false,
        },
      ],
      [
        { showScheduleButton: true },
        {
          scheduleDisabled: false,
          scheduleEditing: false,
          scheduleVisible: true,
          selectionDisabled: false,
        },
      ],
      [
        { isEditing: true, showScheduleButton: true },
        {
          scheduleDisabled: true,
          scheduleEditing: true,
          scheduleVisible: true,
          selectionDisabled: true,
        },
      ],
      [
        { isEditing: true, isEditingScheduled: true },
        {
          scheduleDisabled: false,
          scheduleEditing: false,
          scheduleVisible: true,
          selectionDisabled: true,
        },
      ],
    ];

    expect(cases.map(([options]) => getComposeControlState(options))).toEqual(
      cases.map(([, expected]) => expected),
    );
  });
});
