export const DRIVE_FILE_MIME = 'application/x-drive-file';
export const DRIVE_FOLDER_MIME = 'application/x-drive-folder';

export interface DriveDragPayload {
  fileId?: string;
  folderId?: string;
}

export const readDragPayload = (
  dataTransfer: DataTransfer,
): DriveDragPayload => ({
  fileId: dataTransfer.getData(DRIVE_FILE_MIME) || undefined,
  folderId: dataTransfer.getData(DRIVE_FOLDER_MIME) || undefined,
});

export const carriesDriveItem = (dataTransfer: DataTransfer) =>
  dataTransfer.types.includes(DRIVE_FILE_MIME) ||
  dataTransfer.types.includes(DRIVE_FOLDER_MIME);

export const DRIVE_DROPZONE_ATTRIBUTE = 'data-drive-dropzone';

export const isWithinDriveDropzone = (target: EventTarget | null) =>
  target instanceof Element &&
  target.closest(`[${DRIVE_DROPZONE_ATTRIBUTE}]`) !== null;

export interface DriveItems {
  fileIds: string[];
  folderIds: string[];
}

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
