import { createContext, useContext } from 'react';

export const DEFAULT_COLUMN_WIDTH = 350;
export const MIN_COLUMN_WIDTH = 300;
export const MAX_COLUMN_WIDTH = 700;

export const normalizeColumnWidth = (value: unknown) => {
  const width = typeof value === 'number' ? value : Number(value);

  if (!Number.isFinite(width)) {
    return DEFAULT_COLUMN_WIDTH;
  }

  return Math.min(
    MAX_COLUMN_WIDTH,
    Math.max(MIN_COLUMN_WIDTH, Math.round(width)),
  );
};

interface ColumnWidthContextValue {
  columnId?: string;
  customized?: boolean;
  width?: number;
  onSave?: (width: number) => void;
}

export const ColumnWidthContext = createContext<ColumnWidthContextValue>({});
export const useColumnWidthContext = () => useContext(ColumnWidthContext);
