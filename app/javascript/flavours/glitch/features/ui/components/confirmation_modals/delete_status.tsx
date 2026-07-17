import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { deleteStatus } from 'flavours/glitch/actions/statuses';
import { useAppDispatch } from 'flavours/glitch/store';

import type { BaseConfirmationModalProps } from './confirmation_modal';
import { ConfirmationModal } from './confirmation_modal';

const messages = defineMessages({
  deleteAndRedraftTitle: {
    id: 'confirmations.redraft.title',
    defaultMessage: 'Delete & redraft post?',
  },
  deleteAndRedraftMessage: {
    id: 'confirmations.redraft.message',
    defaultMessage:
      'Are you sure you want to delete this status and re-draft it? Favorites and boosts will be lost, and replies to the original post will be orphaned.',
  },
  deleteAndRedraftConfirm: {
    id: 'confirmations.redraft.confirm',
    defaultMessage: 'Delete & redraft',
  },
  deleteTitle: {
    id: 'confirmations.delete.title',
    defaultMessage: 'Delete post?',
  },
  deleteMessage: {
    id: 'confirmations.delete.message',
    defaultMessage: 'Are you sure you want to delete this status?',
  },
  deleteConfirm: {
    id: 'confirmations.delete.confirm',
    defaultMessage: 'Delete',
  },
  purgeTitle: {
    id: 'confirmations.purge.title',
    defaultMessage: 'Remove post?',
  },
  purgeMessage: {
    id: 'confirmations.purge.message',
    defaultMessage:
      'This post will be deleted permanently and cannot be restored. Do you want to continue?',
  },
  purgeConfirm: {
    id: 'confirmations.purge.confirm',
    defaultMessage: 'Remove',
  },
});

export const ConfirmDeleteStatusModal: React.FC<
  {
    statusId: string;
    withRedraft: boolean;
    purge?: boolean;
    onDeleteSuccess?: () => void;
  } & BaseConfirmationModalProps
> = ({ statusId, withRedraft, purge = false, onClose, onDeleteSuccess }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const onConfirm = useCallback(() => {
    void dispatch(deleteStatus(statusId, withRedraft))
      .then(() => {
        onDeleteSuccess?.();
        onClose();
      })
      .catch(() => {
        // Error handling - still close modal
        onClose();
      });
  }, [dispatch, statusId, withRedraft, onDeleteSuccess, onClose]);

  const variant = purge
    ? {
        title: messages.purgeTitle,
        message: messages.purgeMessage,
        confirm: messages.purgeConfirm,
      }
    : withRedraft
      ? {
          title: messages.deleteAndRedraftTitle,
          message: messages.deleteAndRedraftMessage,
          confirm: messages.deleteAndRedraftConfirm,
        }
      : {
          title: messages.deleteTitle,
          message: messages.deleteMessage,
          confirm: messages.deleteConfirm,
        };

  return (
    <ConfirmationModal
      title={intl.formatMessage(variant.title)}
      message={intl.formatMessage(variant.message)}
      confirm={intl.formatMessage(variant.confirm)}
      onConfirm={onConfirm}
      onClose={onClose}
    />
  );
};
