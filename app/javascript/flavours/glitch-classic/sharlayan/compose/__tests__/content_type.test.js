import { extendContentTypeOptions, getSharlayanContentTypeIcon } from '../content_type';

const intl = {
  formatMessage: ({ id }) => id,
};

describe('Sharlayan content type options', () => {
  it('adds MFM only when the server permits composition', () => {
    const options = extendContentTypeOptions([], intl, true);

    expect(options).toHaveLength(1);
    expect(options[0]).toMatchObject({
      icon: 'brush',
      value: 'text/x-mfm',
      text: 'compose.content-type.mfm',
      meta: 'compose.content-type.mfm_meta',
    });
    expect(extendContentTypeOptions([], intl, false)).toEqual([]);
  });

  it('only supplies an icon override for MFM', () => {
    expect(getSharlayanContentTypeIcon('text/x-mfm')).toMatchObject({ icon: 'brush' });
    expect(getSharlayanContentTypeIcon('text/plain')).toBeNull();
  });
});
