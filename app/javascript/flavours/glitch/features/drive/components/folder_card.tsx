import { useCallback, useMemo, useState } from 'react';

import { useIntl, defineMessages } from 'react-intl';

import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import FolderIcon from '@/material-icons/400-24px/folder.svg?react';
import MoreHorizIcon from '@/material-icons/400-24px/more_horiz.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import type { ApiDriveFolderJSON } from 'flavours/glitch/api_types/drive';
import { Dropdown } from 'flavours/glitch/components/dropdown_menu';
import { Icon } from 'flavours/glitch/components/icon';
import { useAppDispatch } from 'flavours/glitch/store';

import { DRIVE_FOLDER_MIME, carriesDriveItem, readDragPayload } from '../dnd';

const messages = defineMessages({
  rename: { id: 'drive.rename_folder', defaultMessage: 'Rename folder' },
  delete: { id: 'drive.delete_folder', defaultMessage: 'Delete folder' },
  deleteConfirm: {
    id: 'drive.delete_folder_confirm',
    defaultMessage:
      'Delete this folder? Files and folders inside it move back to the drive root.',
  },
  more: { id: 'status.more', defaultMessage: 'More' },
  parent: { id: 'drive.parent_folder', defaultMessage: 'Parent folder' },
});

interface DropTargetProps {
  onDropFile: (fileId: string) => void;
  onDropFolder: (folderId: string) => void;
  canAcceptFolder: (folderId: string) => boolean;
}

const useDropTarget = ({
  onDropFile,
  onDropFolder,
  canAcceptFolder,
}: DropTargetProps) => {
  const [isOver, setIsOver] = useState(false);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    if (!carriesDriveItem(e.dataTransfer)) return;

    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    setIsOver(true);
  }, []);

  const handleDragLeave = useCallback(() => {
    setIsOver(false);
  }, []);

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      if (!carriesDriveItem(e.dataTransfer)) return;

      e.preventDefault();
      setIsOver(false);

      const { fileId, folderId } = readDragPayload(e.dataTransfer);

      if (fileId) {
        onDropFile(fileId);
      } else if (folderId && canAcceptFolder(folderId)) {
        onDropFolder(folderId);
      }
    },
    [onDropFile, onDropFolder, canAcceptFolder],
  );

  return { isOver, handleDragOver, handleDragLeave, handleDrop };
};

export const ParentFolderCard: React.FC<{
  parentId: string | null;
  onOpen: (folderId: string | null) => void;
  onMoveFile: (fileId: string, folderId: string | null) => void;
  onMoveFolder: (folderId: string, parentId: string | null) => void;
  isDescendantOf: (folderId: string, maybeAncestorId: string) => boolean;
}> = ({ parentId, onOpen, onMoveFile, onMoveFolder, isDescendantOf }) => {
  const intl = useIntl();

  const handleClick = useCallback(() => {
    onOpen(parentId);
  }, [onOpen, parentId]);

  const handleDropFile = useCallback(
    (fileId: string) => {
      onMoveFile(fileId, parentId);
    },
    [onMoveFile, parentId],
  );

  const handleDropFolder = useCallback(
    (folderId: string) => {
      onMoveFolder(folderId, parentId);
    },
    [onMoveFolder, parentId],
  );

  const canAcceptFolder = useCallback(
    (draggedId: string) =>
      parentId === null ||
      (draggedId !== parentId && !isDescendantOf(parentId, draggedId)),
    [parentId, isDescendantOf],
  );

  const { isOver, handleDragOver, handleDragLeave, handleDrop } = useDropTarget(
    {
      onDropFile: handleDropFile,
      onDropFolder: handleDropFolder,
      canAcceptFolder,
    },
  );

  return (
    <button
      type='button'
      className={`drive__folder drive__folder--parent${isOver ? ' drive__folder--drop-target' : ''}`}
      onClick={handleClick}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <Icon id='' icon={ArrowUpwardIcon} className='drive__folder__icon' />
      <span className='drive__folder__name'>
        {intl.formatMessage(messages.parent)}
      </span>
    </button>
  );
};

export const FolderCard: React.FC<{
  folder: ApiDriveFolderJSON;
  manageable: boolean;
  onOpen: (folderId: string | null) => void;
  onMoveFile: (fileId: string, folderId: string | null) => void;
  onMoveFolder: (folderId: string, parentId: string | null) => void;
  onRename: (folderId: string, name: string) => void;
  onDelete: (folderId: string) => void;
  isDescendantOf: (folderId: string, maybeAncestorId: string) => boolean;
}> = ({
  folder,
  manageable,
  onOpen,
  onMoveFile,
  onMoveFolder,
  onRename,
  onDelete,
  isDescendantOf,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const handleClick = useCallback(() => {
    onOpen(folder.id);
  }, [onOpen, folder.id]);

  const handleDropFile = useCallback(
    (fileId: string) => {
      onMoveFile(fileId, folder.id);
    },
    [onMoveFile, folder.id],
  );

  const handleDropFolder = useCallback(
    (draggedId: string) => {
      onMoveFolder(draggedId, folder.id);
    },
    [onMoveFolder, folder.id],
  );

  const canAcceptFolder = useCallback(
    (draggedId: string) =>
      draggedId !== folder.id && !isDescendantOf(folder.id, draggedId),
    [isDescendantOf, folder.id],
  );

  const { isOver, handleDragOver, handleDragLeave, handleDrop } = useDropTarget(
    {
      onDropFile: handleDropFile,
      onDropFolder: handleDropFolder,
      canAcceptFolder,
    },
  );

  const handleDragStart = useCallback(
    (e: React.DragEvent) => {
      e.dataTransfer.setData(DRIVE_FOLDER_MIME, folder.id);
      e.dataTransfer.effectAllowed = 'move';
    },
    [folder.id],
  );

  const handleRenameSubmit = useCallback(
    (name: string) => {
      onRename(folder.id, name);
    },
    [onRename, folder.id],
  );

  const handleRename = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'DRIVE_FOLDER_NAME',
        modalProps: {
          initialName: folder.name,
          onSubmit: handleRenameSubmit,
        },
      }),
    );
  }, [dispatch, folder.name, handleRenameSubmit]);

  const handleDelete = useCallback(() => {
    if (window.confirm(intl.formatMessage(messages.deleteConfirm))) {
      onDelete(folder.id);
    }
  }, [intl, folder.id, onDelete]);

  const menu = useMemo(
    () => [
      { text: intl.formatMessage(messages.rename), action: handleRename },
      {
        text: intl.formatMessage(messages.delete),
        action: handleDelete,
        dangerous: true,
      },
    ],
    [intl, handleRename, handleDelete],
  );

  return (
    <div
      className={`drive__folder${isOver ? ' drive__folder--drop-target' : ''}`}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <button
        type='button'
        className='drive__folder__button'
        onClick={handleClick}
        draggable={manageable}
        onDragStart={manageable ? handleDragStart : undefined}
        title={folder.name}
      >
        <Icon id='folder' icon={FolderIcon} className='drive__folder__icon' />
        <span className='drive__folder__name'>{folder.name}</span>
      </button>

      {manageable && (
        <Dropdown items={menu} placement='bottom-end'>
          <button
            type='button'
            className='drive__folder__menu'
            aria-label={intl.formatMessage(messages.more)}
          >
            <Icon id='ellipsis-h' icon={MoreHorizIcon} />
          </button>
        </Dropdown>
      )}
    </div>
  );
};
