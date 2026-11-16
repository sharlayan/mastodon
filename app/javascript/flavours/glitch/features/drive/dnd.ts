export const DRIVE_ITEMS_MIME = 'application/x-drive-items';

export interface DriveItems {
  fileIds: string[];
  folderIds: string[];
}

export const EMPTY_DRIVE_ITEMS: DriveItems = { fileIds: [], folderIds: [] };

export const writeDragPayload = (
  dataTransfer: DataTransfer,
  items: DriveItems,
) => {
  dataTransfer.setData(DRIVE_ITEMS_MIME, JSON.stringify(items));
  dataTransfer.effectAllowed = 'move';
};

const stringList = (value: unknown) =>
  Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];

export const readDragPayload = (dataTransfer: DataTransfer): DriveItems => {
  try {
    const parsed = JSON.parse(dataTransfer.getData(DRIVE_ITEMS_MIME)) as {
      fileIds?: unknown;
      folderIds?: unknown;
    };

    return {
      fileIds: stringList(parsed.fileIds),
      folderIds: stringList(parsed.folderIds),
    };
  } catch {
    return EMPTY_DRIVE_ITEMS;
  }
};

export const carriesDriveItem = (dataTransfer: DataTransfer) =>
  dataTransfer.types.includes(DRIVE_ITEMS_MIME);

export const DRIVE_DROPZONE_ATTRIBUTE = 'data-drive-dropzone';

export const isWithinDriveDropzone = (target: EventTarget | null) =>
  target instanceof Element &&
  target.closest(`[${DRIVE_DROPZONE_ATTRIBUTE}]`) !== null;

export const DRIVE_ITEM_KEY_ATTRIBUTE = 'data-drive-item';

export const fileKey = (id: string) => `file:${id}`;
export const folderKey = (id: string) => `folder:${id}`;

export const itemsFromKeys = (keys: Iterable<string>): DriveItems => {
  const items: DriveItems = { fileIds: [], folderIds: [] };

  for (const key of keys) {
    if (key.startsWith('file:')) items.fileIds.push(key.slice(5));
    else if (key.startsWith('folder:')) items.folderIds.push(key.slice(7));
  }

  return items;
};
