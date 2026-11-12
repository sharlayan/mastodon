import { Fragment, useCallback, useMemo, useRef, useState } from 'react';

import { useIntl, defineMessages, FormattedMessage } from 'react-intl';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import CreateNewFolderIcon from '@/material-icons/400-24px/create_new_folder.svg?react';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import LinkOffIcon from '@/material-icons/400-24px/link_off.svg?react';
import UploadFileIcon from '@/material-icons/400-24px/upload_file.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import type {
  ApiDriveFileJSON,
  ApiDriveUsageJSON,
} from 'flavours/glitch/api_types/drive';
import { EmptyState } from 'flavours/glitch/components/empty_state';
import { Icon } from 'flavours/glitch/components/icon';
import { LoadMore } from 'flavours/glitch/components/load_more';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { useAppDispatch } from 'flavours/glitch/store';

import {
  DRIVE_DROPZONE_ATTRIBUTE,
  DRIVE_ITEM_KEY_ATTRIBUTE,
  carriesDriveItem,
  fileKey,
  folderKey,
  itemsFromKeys,
  readDragPayload,
} from '../dnd';
import type { DriveState } from '../use_drive';

import { FileCard } from './file_card';
import { FolderCard, ParentFolderCard } from './folder_card';

const messages = defineMessages({
  upload: { id: 'drive.upload', defaultMessage: 'Upload' },
  newFolder: { id: 'drive.new_folder', defaultMessage: 'New folder' },
  showUnused: { id: 'drive.show_unused', defaultMessage: 'Unused files' },
  manage: { id: 'drive.manage', defaultMessage: 'Manage' },
  deleteSelected: { id: 'drive.delete_selected', defaultMessage: 'Delete' },
  clearSelection: {
    id: 'drive.clear_selection',
    defaultMessage: 'Clear selection',
  },
  selectionToolbar: {
    id: 'drive.selection_toolbar',
    defaultMessage: 'Selected items',
  },
  deleteSelectedConfirm: {
    id: 'drive.delete_selected_confirm',
    defaultMessage:
      'Delete {count, plural, one {# item} other {# items}}? Files used by a post or page are skipped, and the contents of deleted folders move back to the drive root.',
  },
});

const MARQUEE_THRESHOLD = 4;

interface Point {
  x: number;
  y: number;
}

interface MarqueeBox {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface SelectionState {
  scope: string;
  keys: Set<string>;
  anchor: string | null;
}

interface MarqueeSession {
  pointerId: number;
  start: Point;
  base: Set<string>;
  active: boolean;
}

const isTextEntry = (target: EventTarget | null) =>
  target instanceof HTMLElement &&
  (target.isContentEditable ||
    target instanceof HTMLTextAreaElement ||
    target instanceof HTMLSelectElement ||
    (target instanceof HTMLInputElement && target.type !== 'checkbox'));

export const DriveBrowser: React.FC<{
  drive: DriveState;
  manageable: boolean;
  onSelectFile: (file: ApiDriveFileJSON) => void;
  acceptedTypes?: ApiDriveFileJSON['type'][];
  accept?: string;
}> = ({ drive, manageable, onSelectFile, acceptedTypes, accept }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const pointerTypeRef = useRef<string>('mouse');
  const marqueeRef = useRef<MarqueeSession | null>(null);
  const [isDropping, setIsDropping] = useState(false);
  const [managing, setManaging] = useState(false);
  const [selectionState, setSelectionState] = useState<SelectionState>(() => ({
    scope: '',
    keys: new Set(),
    anchor: null,
  }));
  const [marquee, setMarquee] = useState<MarqueeBox | null>(null);

  const {
    files,
    folders,
    usage,
    childFolders,
    ancestors,
    currentFolder,
    currentFolderId,
    orphanedOnly,
    loading,
    loadingMore,
    uploading,
    hasMore,
    openFolder,
    toggleOrphanedOnly,
    loadMore,
    uploadFiles,
    deleteFile,
    renameFile,
    transferFileToPosts,
    moveFile,
    moveFolder,
    deleteItems,
    createFolder,
    renameFolder,
    deleteFolder,
    isDescendantOf,
  } = drive;

  const selectable = manageable;

  const visibleFiles = acceptedTypes
    ? files.filter((file) => acceptedTypes.includes(file.type))
    : files;

  const itemKeys = useMemo(
    () => [
      ...(orphanedOnly
        ? []
        : childFolders.map((folder) => folderKey(folder.id))),
      ...visibleFiles.map((file) => fileKey(file.id)),
    ],
    [orphanedOnly, childFolders, visibleFiles],
  );

  const scope = `${orphanedOnly ? 'unused' : 'folder'}:${currentFolderId ?? ''}`;
  const activeSelection =
    selectionState.scope === scope ? selectionState : null;
  const anchor = activeSelection?.anchor ?? null;

  const selected = useMemo(() => {
    const known = new Set(itemKeys);
    return new Set(
      [...(activeSelection?.keys ?? [])].filter((key) => known.has(key)),
    );
  }, [activeSelection, itemKeys]);

  const setSelection = useCallback(
    (keys: Set<string>, nextAnchor?: string | null) => {
      setSelectionState((prev) => ({
        scope,
        keys,
        anchor:
          nextAnchor === undefined
            ? prev.scope === scope
              ? prev.anchor
              : null
            : nextAnchor,
      }));
    },
    [scope],
  );

  const selectedItems = useMemo(() => itemsFromKeys(selected), [selected]);

  const openItem = useCallback(
    (key: string) => {
      const { fileIds, folderIds } = itemsFromKeys([key]);
      const file = fileIds[0]
        ? visibleFiles.find((candidate) => candidate.id === fileIds[0])
        : undefined;

      if (file) {
        onSelectFile(file);
      } else if (folderIds[0]) {
        openFolder(folderIds[0]);
      }
    },
    [visibleFiles, onSelectFile, openFolder],
  );

  const toggleItem = useCallback(
    (key: string) => {
      const next = new Set(selected);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      setSelection(next, key);
    },
    [selected, setSelection],
  );

  const handleItemClick = useCallback(
    (key: string, e: React.MouseEvent) => {
      const additive = e.ctrlKey || e.metaKey;
      const coarse = pointerTypeRef.current !== 'mouse';

      if (coarse && !additive && !e.shiftKey) {
        if (selected.size === 0) openItem(key);
        else toggleItem(key);
        return;
      }

      const anchorIndex = anchor ? itemKeys.indexOf(anchor) : -1;

      if (e.shiftKey && anchorIndex !== -1) {
        const index = itemKeys.indexOf(key);
        const range = itemKeys.slice(
          Math.min(anchorIndex, index),
          Math.max(anchorIndex, index) + 1,
        );

        setSelection(
          additive ? new Set([...selected, ...range]) : new Set(range),
        );
        return;
      }

      if (additive) {
        toggleItem(key);
        return;
      }

      setSelection(new Set([key]), key);
    },
    [itemKeys, selected, anchor, openItem, toggleItem, setSelection],
  );

  const clearSelection = useCallback(() => {
    setSelection(new Set(), null);
  }, [setSelection]);

  const handleDeleteSelected = useCallback(() => {
    const count = selectedItems.fileIds.length + selectedItems.folderIds.length;
    if (count === 0) return;

    if (
      window.confirm(
        intl.formatMessage(messages.deleteSelectedConfirm, { count }),
      )
    ) {
      deleteItems(selectedItems);
      clearSelection();
    }
  }, [selectedItems, intl, deleteItems, clearSelection]);

  const openRenameModal = useCallback(
    (key: string) => {
      const { fileIds, folderIds } = itemsFromKeys([key]);
      const file = files.find((candidate) => candidate.id === fileIds[0]);
      const folder = folders.find((candidate) => candidate.id === folderIds[0]);

      if (file) {
        dispatch(
          openModal({
            modalType: 'DRIVE_FILE_NAME',
            modalProps: {
              initialName: file.name ?? '',
              fileName: file.file_name,
              onSubmit: (name: string) => {
                renameFile(file.id, name);
              },
            },
          }),
        );
      } else if (folder) {
        dispatch(
          openModal({
            modalType: 'DRIVE_FOLDER_NAME',
            modalProps: {
              initialName: folder.name,
              onSubmit: (name: string) => {
                renameFolder(folder.id, name);
              },
            },
          }),
        );
      }
    },
    [files, folders, dispatch, renameFile, renameFolder],
  );

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (!selectable || isTextEntry(e.target)) return;

      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'a') {
        e.preventDefault();
        setSelection(new Set(itemKeys));
      } else if (
        selected.size > 0 &&
        (e.key === 'Delete' || (e.metaKey && e.key === 'Backspace'))
      ) {
        e.preventDefault();
        handleDeleteSelected();
      } else if (e.key === 'F2' && selected.size === 1) {
        const [only] = [...selected];
        e.preventDefault();
        if (only) openRenameModal(only);
      }
    },
    [
      selectable,
      itemKeys,
      selected,
      setSelection,
      handleDeleteSelected,
      openRenameModal,
    ],
  );

  const handlePointerDownCapture = useCallback((e: React.PointerEvent) => {
    pointerTypeRef.current = e.pointerType;
  }, []);

  const bodyPoint = useCallback((e: React.PointerEvent): Point | null => {
    const rect = bodyRef.current?.getBoundingClientRect();
    return rect ? { x: e.clientX - rect.left, y: e.clientY - rect.top } : null;
  }, []);

  const handleBodyPointerDown = useCallback(
    (e: React.PointerEvent<HTMLDivElement>) => {
      if (!selectable || e.button !== 0 || e.pointerType !== 'mouse') return;

      const target = e.target as Element;
      if (
        target.closest(
          `[${DRIVE_ITEM_KEY_ATTRIBUTE}], button, a, input, label, select, textarea`,
        )
      ) {
        return;
      }

      const start = bodyPoint(e);
      if (!start) return;

      const keep = e.ctrlKey || e.metaKey || e.shiftKey;
      const base = keep ? new Set(selected) : new Set<string>();

      e.preventDefault();
      containerRef.current?.focus({ preventScroll: true });
      e.currentTarget.setPointerCapture(e.pointerId);
      marqueeRef.current = {
        pointerId: e.pointerId,
        start,
        base,
        active: false,
      };
      setSelection(base, null);
    },
    [selectable, selected, bodyPoint, setSelection],
  );

  const handleBodyPointerMove = useCallback(
    (e: React.PointerEvent<HTMLDivElement>) => {
      const session = marqueeRef.current;
      const body = bodyRef.current;
      if (session?.pointerId !== e.pointerId || !body) return;

      const point = bodyPoint(e);
      if (!point) return;

      if (
        !session.active &&
        Math.hypot(point.x - session.start.x, point.y - session.start.y) <
          MARQUEE_THRESHOLD
      ) {
        return;
      }

      session.active = true;

      const box = {
        left: Math.min(session.start.x, point.x),
        top: Math.min(session.start.y, point.y),
        width: Math.abs(point.x - session.start.x),
        height: Math.abs(point.y - session.start.y),
      };
      setMarquee(box);

      const bodyRect = body.getBoundingClientRect();
      const hits = new Set(session.base);

      body
        .querySelectorAll<HTMLElement>(`[${DRIVE_ITEM_KEY_ATTRIBUTE}]`)
        .forEach((element) => {
          const key = element.getAttribute(DRIVE_ITEM_KEY_ATTRIBUTE);
          const rect = element.getBoundingClientRect();
          const left = rect.left - bodyRect.left;
          const top = rect.top - bodyRect.top;

          if (
            key &&
            left < box.left + box.width &&
            left + rect.width > box.left &&
            top < box.top + box.height &&
            top + rect.height > box.top
          ) {
            hits.add(key);
          }
        });

      setSelection(hits);
    },
    [bodyPoint, setSelection],
  );

  const handleBodyPointerEnd = useCallback(
    (e: React.PointerEvent<HTMLDivElement>) => {
      if (marqueeRef.current?.pointerId !== e.pointerId) return;

      if (e.currentTarget.hasPointerCapture(e.pointerId)) {
        e.currentTarget.releasePointerCapture(e.pointerId);
      }

      marqueeRef.current = null;
      setMarquee(null);
    },
    [],
  );

  const handleUploadClick = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const handleFileInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      if (e.target.files) uploadFiles(e.target.files);
      e.target.value = '';
    },
    [uploadFiles],
  );

  const handleToggleManage = useCallback(() => {
    setManaging((value) => !value);
  }, []);

  const handleNewFolder = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'DRIVE_FOLDER_NAME',
        modalProps: { onSubmit: createFolder },
      }),
    );
  }, [dispatch, createFolder]);

  const handleOpenRoot = useCallback(() => {
    openFolder(null);
  }, [openFolder]);

  const handleRootDragOver = useCallback((e: React.DragEvent) => {
    if (!carriesDriveItem(e.dataTransfer)) return;

    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  }, []);

  const handleRootDrop = useCallback(
    (e: React.DragEvent) => {
      if (!carriesDriveItem(e.dataTransfer)) return;

      e.preventDefault();

      const { fileId, folderId } = readDragPayload(e.dataTransfer);

      if (fileId) {
        moveFile(fileId, null);
      } else if (folderId) {
        moveFolder(folderId, null);
      }
    },
    [moveFile, moveFolder],
  );

  const handleExternalDragOver = useCallback((e: React.DragEvent) => {
    if (!e.dataTransfer.types.includes('Files')) return;

    e.preventDefault();
    e.dataTransfer.dropEffect = 'copy';
    setIsDropping(true);
  }, []);

  const handleExternalDragLeave = useCallback((e: React.DragEvent) => {
    if (e.currentTarget.contains(e.relatedTarget as Node)) return;

    setIsDropping(false);
  }, []);

  const handleExternalDrop = useCallback(
    (e: React.DragEvent) => {
      if (!e.dataTransfer.types.includes('Files')) return;

      e.preventDefault();
      setIsDropping(false);
      uploadFiles(e.dataTransfer.files);
    },
    [uploadFiles],
  );

  const selectionCount = selected.size;
  const className = [
    'drive',
    isDropping && 'drive--dropping',
    managing && 'drive--managing',
    selectable && 'drive--selectable',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      {...{ [DRIVE_DROPZONE_ATTRIBUTE]: true }}
      ref={containerRef}
      className={className}
      tabIndex={selectable ? -1 : undefined}
      onDragOver={handleExternalDragOver}
      onDragLeave={handleExternalDragLeave}
      onDrop={handleExternalDrop}
      onKeyDown={handleKeyDown}
      onPointerDownCapture={handlePointerDownCapture}
    >
      {orphanedOnly ? (
        <p className='drive__hint'>
          <FormattedMessage
            id='drive.unused_hint'
            defaultMessage='Files across every folder that no post is using. Safe to delete.'
          />
        </p>
      ) : (
        <nav className='drive__breadcrumb'>
          <button
            type='button'
            className={
              currentFolderId === null
                ? 'drive__breadcrumb__crumb drive__breadcrumb__crumb--active'
                : 'drive__breadcrumb__crumb'
            }
            onClick={handleOpenRoot}
            onDragOver={handleRootDragOver}
            onDrop={handleRootDrop}
          >
            <FormattedMessage id='drive.root' defaultMessage='Drive' />
          </button>

          {ancestors.map((folder) => (
            <Fragment key={folder.id}>
              <span className='drive__breadcrumb__separator' aria-hidden>
                /
              </span>

              <BreadcrumbCrumb
                id={folder.id}
                name={folder.name}
                isCurrent={folder.id === currentFolderId}
                onOpen={openFolder}
                onMoveFile={moveFile}
                onMoveFolder={moveFolder}
              />
            </Fragment>
          ))}
        </nav>
      )}

      <div className='drive__toolbar'>
        <button
          type='button'
          className='button'
          onClick={handleUploadClick}
          disabled={uploading}
        >
          <Icon id='upload' icon={UploadFileIcon} />
          {intl.formatMessage(messages.upload)}
        </button>

        {manageable && (
          <button
            type='button'
            className={`button button-secondary drive__manage${managing ? ' drive__manage--active' : ''}`}
            onClick={handleToggleManage}
            aria-pressed={managing}
          >
            <Icon id='pencil' icon={EditIcon} />
            {intl.formatMessage(messages.manage)}
          </button>
        )}

        {(managing || selectable) && (
          <button
            type='button'
            className='button button-secondary'
            onClick={handleNewFolder}
            disabled={orphanedOnly}
          >
            <Icon id='folder-plus' icon={CreateNewFolderIcon} />
            {intl.formatMessage(messages.newFolder)}
          </button>
        )}

        <button
          type='button'
          className={`button button-secondary drive__filter${orphanedOnly ? ' drive__filter--active' : ''}`}
          onClick={toggleOrphanedOnly}
          aria-pressed={orphanedOnly}
        >
          <Icon id='' icon={LinkOffIcon} />
          {intl.formatMessage(messages.showUnused)}
        </button>

        <input
          ref={fileInputRef}
          type='file'
          multiple
          accept={accept}
          style={{ display: 'none' }}
          onChange={handleFileInputChange}
        />
      </div>

      {selectable && selectionCount > 0 && (
        <div
          className='drive__selection'
          role='toolbar'
          aria-label={intl.formatMessage(messages.selectionToolbar)}
        >
          <span className='drive__selection__count'>
            <FormattedMessage
              id='drive.selected_count'
              defaultMessage='{count, plural, one {# item selected} other {# items selected}}'
              values={{ count: selectionCount }}
            />
          </span>

          <button
            type='button'
            className='button button-secondary drive__selection__delete'
            onClick={handleDeleteSelected}
          >
            <Icon id='trash' icon={DeleteIcon} />
            {intl.formatMessage(messages.deleteSelected)}
          </button>

          <button
            type='button'
            className='button button-secondary'
            onClick={clearSelection}
          >
            <Icon id='times' icon={CloseIcon} />
            {intl.formatMessage(messages.clearSelection)}
          </button>
        </div>
      )}

      {usage && <DriveUsage usage={usage} />}

      {managing && !orphanedOnly && (
        <p className='drive__hint'>
          <FormattedMessage
            id='drive.manage_hint'
            defaultMessage='Drag files and folders to move them. Use the pencil to rename them.'
          />
        </p>
      )}

      <div
        ref={bodyRef}
        role='presentation'
        className={`drive__body${marquee ? ' drive__body--selecting' : ''}`}
        onPointerDown={handleBodyPointerDown}
        onPointerMove={handleBodyPointerMove}
        onPointerUp={handleBodyPointerEnd}
        onPointerCancel={handleBodyPointerEnd}
      >
        {!orphanedOnly && (
          <div className='drive__folders'>
            {currentFolder && (
              <ParentFolderCard
                parentId={currentFolder.parent_id}
                onOpen={openFolder}
                onMoveFile={moveFile}
                onMoveFolder={moveFolder}
                isDescendantOf={isDescendantOf}
              />
            )}

            {childFolders.map((folder) => (
              <FolderCard
                key={folder.id}
                folder={folder}
                manageable={managing}
                selectable={selectable}
                selected={selected.has(folderKey(folder.id))}
                onOpen={openFolder}
                onItemClick={handleItemClick}
                onToggleItem={toggleItem}
                onMoveFile={moveFile}
                onMoveFolder={moveFolder}
                onRename={renameFolder}
                onDelete={deleteFolder}
                isDescendantOf={isDescendantOf}
              />
            ))}
          </div>
        )}

        {loading ? (
          <LoadingIndicator />
        ) : visibleFiles.length === 0 ? (
          <EmptyState
            title={
              orphanedOnly ? (
                <FormattedMessage
                  id='drive.no_unused'
                  defaultMessage='Every file is in use.'
                />
              ) : (
                <FormattedMessage
                  id='drive.empty'
                  defaultMessage='No files here yet.'
                />
              )
            }
            message={
              <FormattedMessage
                id='drive.empty_hint'
                defaultMessage='Upload a file, or drag one in from your computer.'
              />
            }
          />
        ) : (
          <div className='drive__grid'>
            {visibleFiles.map((file) => (
              <FileCard
                key={file.id}
                file={file}
                manageable={managing}
                draggable={managing && !orphanedOnly}
                selectable={selectable}
                selected={selected.has(fileKey(file.id))}
                onSelect={onSelectFile}
                onItemClick={handleItemClick}
                onToggleItem={toggleItem}
                onDelete={deleteFile}
                onRename={renameFile}
                onTransferToPosts={transferFileToPosts}
              />
            ))}
          </div>
        )}

        {marquee && (
          <div
            className='drive__marquee'
            style={{
              left: marquee.left,
              top: marquee.top,
              width: marquee.width,
              height: marquee.height,
            }}
            aria-hidden
          />
        )}
      </div>

      {!loading && hasMore && (
        <LoadMore onClick={loadMore} loading={loadingMore} />
      )}
    </div>
  );
};

const formatBytes = (bytes: number) => {
  if (bytes < 1024) return `${bytes} B`;

  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1024;
  let unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }

  const digits = value >= 100 || Number.isInteger(value) ? 0 : 1;

  return `${value.toFixed(digits)} ${units[unit]}`;
};

const DriveUsage: React.FC<{ usage: ApiDriveUsageJSON }> = ({ usage }) => {
  const unlimited = usage.limit <= 0;
  const percent = unlimited
    ? 0
    : Math.min(100, Math.ceil((usage.used / usage.limit) * 1000) / 10);

  return (
    <div className='drive__usage'>
      <div className='drive__usage__label'>
        <span className='drive__usage__title'>
          <FormattedMessage id='drive.storage' defaultMessage='Storage' />
        </span>
        <span className='drive__usage__value'>
          {unlimited ? (
            <FormattedMessage
              id='drive.usage_unlimited'
              defaultMessage='{used} used'
              values={{ used: formatBytes(usage.used) }}
            />
          ) : (
            <FormattedMessage
              id='drive.usage'
              defaultMessage='{used} of {limit} used'
              values={{
                used: formatBytes(usage.used),
                limit: formatBytes(usage.limit),
              }}
            />
          )}
        </span>
      </div>

      {!unlimited && (
        <div
          className='drive__usage__bar'
          role='progressbar'
          aria-valuenow={percent}
          aria-valuemin={0}
          aria-valuemax={100}
        >
          <div
            className={`drive__usage__bar__fill${percent >= 90 ? ' drive__usage__bar__fill--full' : ''}`}
            style={{ width: `${percent}%` }}
          />
        </div>
      )}
    </div>
  );
};

const BreadcrumbCrumb: React.FC<{
  id: string;
  name: string;
  isCurrent: boolean;
  onOpen: (folderId: string | null) => void;
  onMoveFile: (fileId: string, folderId: string | null) => void;
  onMoveFolder: (folderId: string, parentId: string | null) => void;
}> = ({ id, name, isCurrent, onOpen, onMoveFile, onMoveFolder }) => {
  const handleClick = useCallback(() => {
    onOpen(id);
  }, [onOpen, id]);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    if (!carriesDriveItem(e.dataTransfer)) return;

    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  }, []);

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      if (!carriesDriveItem(e.dataTransfer)) return;

      e.preventDefault();

      const { fileId, folderId } = readDragPayload(e.dataTransfer);

      if (fileId) {
        onMoveFile(fileId, id);
      } else if (folderId && folderId !== id) {
        onMoveFolder(folderId, id);
      }
    },
    [onMoveFile, onMoveFolder, id],
  );

  return (
    <button
      type='button'
      className={`drive__breadcrumb__crumb${isCurrent ? ' drive__breadcrumb__crumb--active' : ''}`}
      onClick={handleClick}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
    >
      {name}
    </button>
  );
};
