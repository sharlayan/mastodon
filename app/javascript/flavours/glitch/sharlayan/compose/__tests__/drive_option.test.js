import { addDriveUploadOption, selectDriveUploadOption } from '../drive_option';

describe('Drive upload option', () => {
  it('only adds Drive when enabled', () => {
    const intl = { formatMessage: ({ id }) => id };

    expect(addDriveUploadOption([], intl, false)).toEqual([]);
    expect(addDriveUploadOption([], intl, true)[0]).toMatchObject({ icon: 'cloud', value: 'drive', text: 'compose.attach.drive' });
  });

  it('handles only the Drive selection', () => {
    const onDriveOpen = vi.fn();

    expect(selectDriveUploadOption('upload', onDriveOpen)).toBe(false);
    expect(selectDriveUploadOption('drive', onDriveOpen)).toBe(true);
    expect(onDriveOpen).toHaveBeenCalledOnce();
  });
});
