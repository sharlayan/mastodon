import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { discardCompose } from 'flavours/glitch/actions/compose';
import { openModal } from 'flavours/glitch/actions/modal';
import { useAppDispatch } from 'flavours/glitch/store';

import type { BaseConfirmationModalProps } from './confirmation_modal';
import { ConfirmationModal } from './confirmation_modal';

const messages = defineMessages({
  title: {
    id: 'confirmations.resume_draft.title',
    defaultMessage: 'You have an unfinished post',
  },
  message: {
    id: 'confirmations.resume_draft.message',
    defaultMessage: 'You can continue writing it or compose a new post.',
  },
  resume: {
    id: 'confirmations.resume_draft.resume',
    defaultMessage: 'Continue writing',
  },
  reset: {
    id: 'confirmations.resume_draft.reset',
    defaultMessage: 'Reset and compose a new post',
  },
});

export const ConfirmResumeDraftModal: React.FC<BaseConfirmationModalProps> = ({
  onClose,
}) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();

  const onConfirm = useCallback(() => {
    dispatch(discardCompose());
    dispatch(
      openModal({
        modalType: 'INLINE_COMPOSE',
        modalProps: { title: 'compose', discardOnClose: false },
      }),
    );
  }, [dispatch]);

  const onCancel = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'INLINE_COMPOSE',
        modalProps: { title: 'compose', discardOnClose: false },
      }),
    );
  }, [dispatch]);

  return (
    <ConfirmationModal
      title={intl.formatMessage(messages.title)}
      message={intl.formatMessage(messages.message)}
      cancel={intl.formatMessage(messages.resume)}
      confirm={intl.formatMessage(messages.reset)}
      onConfirm={onConfirm}
      onCancel={onCancel}
      onClose={onClose}
    />
  );
};
