import type { CSSProperties } from 'react';

const UPLOAD_GRID_COLUMNS = 3;

export const getUploadGridStyle = (size: number): CSSProperties | undefined => {
  if (size <= 4) return undefined;

  const rows = Math.ceil(size / UPLOAD_GRID_COLUMNS);

  return {
    aspectRatio: `${UPLOAD_GRID_COLUMNS * 3} / ${rows * 2}`,
    gridTemplateColumns: `repeat(${UPLOAD_GRID_COLUMNS}, 1fr)`,
    gridTemplateRows: `repeat(${rows}, 1fr)`,
  };
};
