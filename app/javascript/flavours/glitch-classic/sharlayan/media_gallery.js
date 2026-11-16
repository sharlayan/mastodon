export const getMediaGalleryGrid = size => {
  const columns = Math.max(Math.ceil(Math.sqrt(size)), 2);

  return { columns, rows: Math.ceil(size / columns) };
};

export const getMediaGalleryItemDimensions = (size, index) => {
  const { columns } = getMediaGalleryGrid(size);
  const remaining = (-size % columns + columns) % columns;
  const largeCount = Math.floor(remaining / 3);
  const mediumCount = remaining % 3;

  if (size === 1 || index < largeCount) return { width: 100, height: 100 };
  if (size === 2 || index < largeCount + mediumCount) return { width: 50, height: 100 };

  return { width: 50, height: 50 };
};

export const shouldAutoplayMedia = ({ attachmentType, autoplay, disableGifvAutoplay }) =>
  !(disableGifvAutoplay && attachmentType === 'gifv') && autoplay;
