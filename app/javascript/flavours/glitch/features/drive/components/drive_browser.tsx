import { Fragment, useCallback, useRef, useState } from 'react';

import { useIntl, defineMessages, FormattedMessage } from 'react-intl';

import CreateNewFolderIcon from '@/material-icons/400-24px/create_new_folder.svg?react';
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
  carriesDriveItem,
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
});

export const DriveBrowser: React.FC<{
  drive: DriveState;
  manageable: boolean;
  onSelectFile: (file: ApiDriveFileJSON) => void;
}> = ({ drive, manageable, onSelectFile }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isDropping, setIsDropping] = useState(false);
  const [managing, setManaging] = useState(false);

  const {
    files,
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
    createFolder,
    renameFolder,
    moveFolder,
    deleteFolder,
    isDescendantOf,
  } = drive;

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

  return (
    <div
      {...{ [DRIVE_DROPZONE_ATTRIBUTE]: true }}
      className={`drive${isDropping ? ' drive--dropping' : ''}${managing ? ' drive--managing' : ''}`}
      onDragOver={handleExternalDragOver}
      onDragLeave={handleExternalDragLeave}
      onDrop={handleExternalDrop}
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

        {managing && (
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
          style={{ display: 'none' }}
          onChange={handleFileInputChange}
        />
      </div>

      {usage && <DriveUsage usage={usage} />}

      {managing && !orphanedOnly && (
        <p className='drive__hint'>
          <FormattedMessage
            id='drive.manage_hint'
            defaultMessage='Drag files and folders to move them. Use the pencil to rename them.'
          />
        </p>
      )}

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
              onOpen={openFolder}
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
      ) : files.length === 0 ? (
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
        <>
          <div className='drive__grid'>
            {files.map((file) => (
              <FileCard
                key={file.id}
                file={file}
                manageable={managing}
                draggable={managing && !orphanedOnly}
                onSelect={onSelectFile}
                onDelete={deleteFile}
                onRename={renameFile}
                onTransferToPosts={transferFileToPosts}
              />
            ))}
          </div>

          {hasMore && <LoadMore onClick={loadMore} loading={loadingMore} />}
        </>
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
