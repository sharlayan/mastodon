import { useCallback, useMemo, useState } from 'react';

import { useIntl, defineMessages } from 'react-intl';

import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import FolderIcon from '@/material-icons/400-24px/folder.svg?react';
import MoreHorizIcon from '@/material-icons/400-24px/more_horiz.svg?react';
import { openModal } from 'flavours/glitch-classic/actions/modal';
import type { ApiDriveFolderJSON } from 'flavours/glitch-classic/api_types/drive';
import { Dropdown } from 'flavours/glitch-classic/components/dropdown_menu';
import { Icon } from 'flavours/glitch-classic/components/icon';
import { useAppDispatch } from 'flavours/glitch-classic/store';

import {
  DRIVE_ITEM_KEY_ATTRIBUTE,
  carriesDriveItem,
  folderKey,
  readDragPayload,
  writeDragPayload,
} from '../dnd';
import type { DriveItems } from '../dnd';

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
  select: { id: 'drive.select_item', defaultMessage: 'Select {name}' },
});

export const useDriveDropTarget = (
  onDropItems: (items: DriveItems) => void,
) => {
  const [isOver, setIsOver] = useState(false);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    if (!carriesDriveItem(e.dataTransfer)) return;

    e.preventDefault();
    e.stopPropagation();
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
      e.stopPropagation();
      setIsOver(false);
      onDropItems(readDragPayload(e.dataTransfer));
    },
    [onDropItems],
  );

  return { isOver, handleDragOver, handleDragLeave, handleDrop };
};

export const ParentFolderCard: React.FC<{
  parentId: string | null;
  onOpen: (folderId: string | null) => void;
  onMoveItems: (items: DriveItems, folderId: string | null) => void;
}> = ({ parentId, onOpen, onMoveItems }) => {
  const intl = useIntl();

  const handleClick = useCallback(() => {
    onOpen(parentId);
  }, [onOpen, parentId]);

  const handleDropItems = useCallback(
    (items: DriveItems) => {
      onMoveItems(items, parentId);
    },
    [onMoveItems, parentId],
  );

  const { isOver, handleDragOver, handleDragLeave, handleDrop } =
    useDriveDropTarget(handleDropItems);

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
  selectable?: boolean;
  selected?: boolean;
  onOpen: (folderId: string | null) => void;
  onItemClick?: (key: string, e: React.MouseEvent) => void;
  onToggleItem?: (key: string) => void;
  onDragItem?: (key: string, e: React.DragEvent) => void;
  onMoveItems: (items: DriveItems, folderId: string | null) => void;
  onRename: (folderId: string, name: string) => void;
  onDelete: (folderId: string) => void;
}> = ({
  folder,
  manageable,
  selectable = false,
  selected = false,
  onOpen,
  onItemClick,
  onToggleItem,
  onDragItem,
  onMoveItems,
  onRename,
  onDelete,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const key = folderKey(folder.id);

  const handleClick = useCallback(
    (e: React.MouseEvent) => {
      if (selectable && onItemClick) {
        onItemClick(key, e);
        return;
      }

      onOpen(folder.id);
    },
    [onOpen, onItemClick, selectable, key, folder.id],
  );

  const handleDoubleClick = useCallback(() => {
    if (selectable) onOpen(folder.id);
  }, [onOpen, selectable, folder.id]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (!selectable) return;

      if (e.key === 'Enter') {
        e.preventDefault();
        onOpen(folder.id);
      } else if (e.key === ' ') {
        e.preventDefault();
        onToggleItem?.(key);
      }
    },
    [onOpen, onToggleItem, selectable, key, folder.id],
  );

  const handleCheckboxChange = useCallback(() => {
    onToggleItem?.(key);
  }, [key, onToggleItem]);

  const stopPropagation = useCallback((e: React.SyntheticEvent) => {
    e.stopPropagation();
  }, []);

  const handleDropItems = useCallback(
    (items: DriveItems) => {
      onMoveItems(items, folder.id);
    },
    [onMoveItems, folder.id],
  );

  const { isOver, handleDragOver, handleDragLeave, handleDrop } =
    useDriveDropTarget(handleDropItems);

  const handleDragStart = useCallback(
    (e: React.DragEvent) => {
      if (onDragItem) {
        onDragItem(key, e);
        return;
      }

      writeDragPayload(e.dataTransfer, {
        fileIds: [],
        folderIds: [folder.id],
      });
    },
    [folder.id, key, onDragItem],
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
      className={`drive__folder${isOver ? ' drive__folder--drop-target' : ''}${selected ? ' drive__folder--selected' : ''}`}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
      {...{ [DRIVE_ITEM_KEY_ATTRIBUTE]: key }}
    >
      {selectable && (
        <input
          type='checkbox'
          className='drive__item-check drive__item-check--inline'
          checked={selected}
          onChange={handleCheckboxChange}
          onClick={stopPropagation}
          onDoubleClick={stopPropagation}
          aria-label={intl.formatMessage(messages.select, {
            name: folder.name,
          })}
        />
      )}

      <button
        type='button'
        className='drive__folder__button'
        onClick={handleClick}
        onDoubleClick={handleDoubleClick}
        onKeyDown={handleKeyDown}
        draggable={manageable || selectable}
        onDragStart={manageable || selectable ? handleDragStart : undefined}
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
