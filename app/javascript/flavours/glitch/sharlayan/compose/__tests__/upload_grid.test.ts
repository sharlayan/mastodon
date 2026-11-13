import { getUploadGridStyle } from '../upload_grid';

describe('getUploadGridStyle', () => {
  it('keeps the stock layout up to four uploads and uses a three-column grid of 3:2 tiles beyond that', () => {
    expect(getUploadGridStyle(4)).toBeUndefined();
    expect(getUploadGridStyle(5)).toEqual({
      aspectRatio: '9 / 4',
      gridTemplateColumns: 'repeat(3, 1fr)',
      gridTemplateRows: 'repeat(2, 1fr)',
    });
    expect(getUploadGridStyle(10)).toEqual({
      aspectRatio: '9 / 8',
      gridTemplateColumns: 'repeat(3, 1fr)',
      gridTemplateRows: 'repeat(4, 1fr)',
    });
  });
});
