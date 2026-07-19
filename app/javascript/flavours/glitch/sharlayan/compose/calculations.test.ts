import {
  canSubmitCompose,
  getComposeControlState,
  getComposeOverflowStart,
  getSharlayanSubmitLabel,
  shouldShowComposeLanguage,
  shouldShowScheduleButton,
} from './calculations';

describe('Sharlayan compose calculations', () => {
  it.each([
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
  ])('selects the submit label for %o', (options, expected) => {
    expect(getSharlayanSubmitLabel(options)).toBe(expected);
  });

  it.each([
    [{ fullText: '12345', maxChars: 5 }, true],
    [{ fullText: '123456', maxChars: 5 }, false],
    [{ fullText: '', maxChars: 5, isSubmitting: true }, false],
    [{ fullText: '', maxChars: 5, isUploading: true }, false],
    [{ fullText: '', maxChars: 5, isChangingUpload: true }, false],
  ])('preserves submit availability for %o', (options, expected) => {
    expect(canSubmitCompose(options)).toBe(expected);
  });

  it('deducts the content warning budget from the overflow boundary', () => {
    expect(
      getComposeOverflowStart({
        text: 'abcdef',
        maxChars: 8,
        spoiler: true,
        spoilerText: '123',
      }),
    ).toBe(5);
    expect(
      getComposeOverflowStart({
        text: 'abcdef',
        maxChars: 8,
        spoiler: false,
        spoilerText: '123',
      }),
    ).toBe(-1);
  });

  it('uses the same shortened URL boundary as the character counter', () => {
    const text = `1234567 https://example.com/a-very-long-path tail`;

    expect(getComposeOverflowStart({ text, maxChars: 30 })).toBe(
      text.indexOf('https://'),
    );
  });

  it('keeps the schedule control visible while editing a scheduled post', () => {
    expect(shouldShowScheduleButton(false, true)).toBe(true);
    expect(shouldShowScheduleButton(false, false)).toBe(false);
  });

  it('keeps the upstream language selector unless the local setting hides it', () => {
    expect(shouldShowComposeLanguage(false)).toBe(true);
    expect(shouldShowComposeLanguage(true)).toBe(false);
  });

  it.each([
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
  ])('preserves compose control state for %o', (options, expected) => {
    expect(getComposeControlState(options)).toEqual(expected);
  });
});
