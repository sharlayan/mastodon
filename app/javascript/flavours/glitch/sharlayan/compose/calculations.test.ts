import {
  canSubmitCompose,
  getComposeControlState,
  getComposeOverflowStart,
  getSharlayanSubmitLabel,
  shouldShowComposeLanguage,
  shouldShowScheduleButton,
} from './calculations';

describe('Sharlayan compose calculations', () => {
  it('selects the submit label by editing, schedule, reply and toot preference', () => {
    const cases: [Parameters<typeof getSharlayanSubmitLabel>[0], string][] = [
      [
        {
          isEditing: true,
          scheduledAt: '2026-07-17T01:00:00Z',
          isInReply: true,
          usePublishToot: true,
        },
        'saveChanges',
      ],
      [
        {
          scheduledAt: '2026-07-17T01:00:00Z',
          isInReply: true,
          usePublishToot: true,
        },
        'schedule',
      ],
      [{ isInReply: true, usePublishToot: true }, 'reply'],
      [{ usePublishToot: true }, 'publishToot'],
      [{}, 'publish'],
    ];

    expect(cases.map(([options]) => getSharlayanSubmitLabel(options))).toEqual(
      cases.map(([, expected]) => expected),
    );
  });

  it('preserves submit availability for length and busy states', () => {
    const cases: [Parameters<typeof canSubmitCompose>[0], boolean][] = [
      [{ fullText: '12345', maxChars: 5 }, true],
      [{ fullText: '123456', maxChars: 5 }, false],
      [{ fullText: '', maxChars: 5, isSubmitting: true }, false],
      [{ fullText: '', maxChars: 5, isUploading: true }, false],
      [{ fullText: '', maxChars: 5, isChangingUpload: true }, false],
    ];

    expect(cases.map(([options]) => canSubmitCompose(options))).toEqual(
      cases.map(([, expected]) => expected),
    );
  });

  it('deducts the content warning budget from the overflow boundary', () => {
    expect(
      getComposeOverflowStart({
        text: 'abcdef',
        countedText: '123abcdef',
        maxChars: 8,
        spoiler: true,
        spoilerText: '123',
      }),
    ).toBe(5);
    expect(
      getComposeOverflowStart({
        text: 'abcdef',
        countedText: 'abcdef',
        maxChars: 8,
        spoiler: false,
        spoilerText: '123',
      }),
    ).toBe(-1);
  });

  it('uses the same shortened URL boundary as the character counter', () => {
    const text = `1234567 https://example.com/a-very-long-path tail`;

    expect(
      getComposeOverflowStart({
        text,
        countedText: `1234567 ${'x'.repeat(23)} tail`,
        maxChars: 30,
      }),
    ).toBe(text.indexOf('https://'));
  });

  it('keeps overflow boundary mapping disabled until the counted text exceeds the limit', () => {
    expect(
      getComposeOverflowStart({
        text: 'raw text that would otherwise exceed the limit',
        countedText: '12345',
        maxChars: 5,
      }),
    ).toBe(-1);
  });

  it('keeps the schedule control visible while editing a scheduled post', () => {
    expect(shouldShowScheduleButton(false, true)).toBe(true);
    expect(shouldShowScheduleButton(false, false)).toBe(false);
  });

  it('keeps the upstream language selector unless the local setting hides it', () => {
    expect(shouldShowComposeLanguage(false)).toBe(true);
    expect(shouldShowComposeLanguage(true)).toBe(false);
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
