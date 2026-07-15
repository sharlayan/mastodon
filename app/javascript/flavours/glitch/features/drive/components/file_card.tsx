import { useCallback } from 'react';

import { useIntl, defineMessages, FormattedMessage } from 'react-intl';

import CloudDownloadIcon from '@/material-icons/400-24px/cloud_download.svg?react';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import LinkOffIcon from '@/material-icons/400-24px/link_off.svg?react';
import { showAlert } from 'flavours/glitch/actions/alerts';
import { openModal } from 'flavours/glitch/actions/modal';
import type { ApiDriveFileJSON } from 'flavours/glitch/api_types/drive';
import { Icon } from 'flavours/glitch/components/icon';
import { useAppDispatch } from 'flavours/glitch/store';

import { DRIVE_FILE_MIME } from '../dnd';

const messages = defineMessages({
  delete: { id: 'drive.delete', defaultMessage: 'Delete' },
  rename: { id: 'drive.rename_file', defaultMessage: 'Rename file' },
  deleteConfirm: {
    id: 'drive.delete_confirm',
    defaultMessage: 'Delete this drive file permanently?',
  },
  unattached: {
    id: 'drive.unattached',
    defaultMessage: 'Not used in any post',
  },
  attached: {
    id: 'drive.delete_attached',
    defaultMessage: 'Attached to a post, cannot be deleted',
  },
  attachedError: {
    id: 'drive.delete_attached_error',
    defaultMessage: 'Files attached to a post cannot be deleted.',
  },
  transferToPosts: {
    id: 'drive.transfer_to_posts',
    defaultMessage: 'Move to post attachments',
  },
  transferToPostsConfirm: {
    id: 'drive.transfer_to_posts_confirm',
    defaultMessage:
      'Move this file out of Drive? A separate media copy will be assigned to every post using it, and the Drive file will be removed.',
  },
});

const formatSize = (size: number | null) => {
  if (!size) return null;

  const units = ['B', 'KB', 'MB', 'GB'];
  let value = size;
  let unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }

  return `${value < 10 && unit > 0 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
};

export const FileCard: React.FC<{
  file: ApiDriveFileJSON;
  manageable: boolean;
  draggable: boolean;
  onSelect: (file: ApiDriveFileJSON) => void;
  onDelete: (fileId: string) => void;
  onRename: (fileId: string, name: string) => void;
  onTransferToPosts: (fileId: string) => void;
}> = ({
  file,
  manageable,
  draggable,
  onSelect,
  onDelete,
  onRename,
  onTransferToPosts,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const handleClick = useCallback(() => {
    onSelect(file);
  }, [file, onSelect]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        onSelect(file);
      }
    },
    [file, onSelect],
  );

  const handleDragStart = useCallback(
    (e: React.DragEvent) => {
      e.dataTransfer.setData(DRIVE_FILE_MIME, file.id);
      e.dataTransfer.effectAllowed = 'move';
    },
    [file.id],
  );

  const handleDelete = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();

      if (!file.orphaned) {
        dispatch(showAlert({ message: messages.attachedError }));
        return;
      }

      if (window.confirm(intl.formatMessage(messages.deleteConfirm))) {
        onDelete(file.id);
      }
    },
    [file.id, file.orphaned, onDelete, dispatch, intl],
  );

  const handleRenameSubmit = useCallback(
    (name: string) => {
      onRename(file.id, name);
    },
    [onRename, file.id],
  );

  const handleRename = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();

      dispatch(
        openModal({
          modalType: 'DRIVE_FILE_NAME',
          modalProps: {
            initialName: file.name ?? '',
            fileName: file.file_name,
            onSubmit: handleRenameSubmit,
          },
        }),
      );
    },
    [dispatch, file.name, file.file_name, handleRenameSubmit],
  );

  const handleTransferToPosts = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();

      if (window.confirm(intl.formatMessage(messages.transferToPostsConfirm))) {
        onTransferToPosts(file.id);
      }
    },
    [file.id, intl, onTransferToPosts],
  );

  const size = formatSize(file.size);

  return (
    <div
      className='drive__file'
      role='button'
      tabIndex={0}
      draggable={draggable}
      onDragStart={draggable ? handleDragStart : undefined}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
      title={file.name ?? undefined}
    >
      <div className='drive__file__preview'>
        {file.type === 'image' || file.type === 'gifv' ? (
          <img
            src={file.preview_url}
            alt={file.description ?? ''}
            loading='lazy'
            draggable={false}
          />
        ) : (
          <div className='drive__file__placeholder'>
            <span>{file.type}</span>
          </div>
        )}

        {file.orphaned && (
          <span
            className='drive__file__badge'
            title={intl.formatMessage(messages.unattached)}
          >
            <Icon id='' icon={LinkOffIcon} />
            <FormattedMessage id='drive.unused' defaultMessage='Unused' />
          </span>
        )}

        {manageable && (
          <div className='drive__file__actions'>
            <button
              type='button'
              className='drive__file__action'
              onClick={handleRename}
              aria-label={intl.formatMessage(messages.rename)}
              title={intl.formatMessage(messages.rename)}
            >
              <Icon id='pencil' icon={EditIcon} />
            </button>

            {!file.orphaned && file.type !== 'unknown' && (
              <button
                type='button'
                className='drive__file__action'
                onClick={handleTransferToPosts}
                aria-label={intl.formatMessage(messages.transferToPosts)}
                title={intl.formatMessage(messages.transferToPosts)}
              >
                <Icon id='cloud-download' icon={CloudDownloadIcon} />
              </button>
            )}

            <button
              type='button'
              className={`drive__file__action drive__file__action--dangerous${file.orphaned ? '' : ' drive__file__action--locked'}`}
              onClick={handleDelete}
              aria-label={intl.formatMessage(
                file.orphaned ? messages.delete : messages.attached,
              )}
              title={intl.formatMessage(
                file.orphaned ? messages.delete : messages.attached,
              )}
            >
              <Icon id='trash' icon={DeleteIcon} />
            </button>
          </div>
        )}
      </div>

      <div className='drive__file__meta'>
        <span className='drive__file__name'>{file.name}</span>
        {size && <span className='drive__file__size'>{size}</span>}
      </div>
    </div>
  );
};
