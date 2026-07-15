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
