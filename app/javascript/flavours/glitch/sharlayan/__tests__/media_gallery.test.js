import { getMediaGalleryGrid, getMediaGalleryItemDimensions, shouldAutoplayMedia } from '../media_gallery';

describe('Sharlayan media gallery helpers', () => {
  it('lays out remote attachment counts in a compact grid', () => {
    expect(getMediaGalleryGrid(16)).toEqual({ columns: 4, rows: 4 });
    expect(getMediaGalleryItemDimensions(1, 0)).toEqual({ width: 100, height: 100 });
    expect(getMediaGalleryItemDimensions(2, 1)).toEqual({ width: 50, height: 100 });
  });

  it('only disables autoplay for GIFV attachments', () => {
    expect(shouldAutoplayMedia({ attachmentType: 'gifv', autoplay: true, disableGifvAutoplay: true })).toBe(false);
    expect(shouldAutoplayMedia({ attachmentType: 'video', autoplay: true, disableGifvAutoplay: true })).toBe(true);
  });
});
