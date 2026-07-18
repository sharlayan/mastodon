import { useCallback, useEffect } from 'react';

import { FormattedMessage, defineMessages, useIntl } from 'react-intl';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import { mountCompose, unmountCompose } from 'flavours/glitch/actions/compose';
import { IconButton } from 'flavours/glitch/components/icon_button';
import ComposeFormContainer from 'flavours/glitch/features/compose/containers/compose_form_container';
import { useAppDispatch } from 'flavours/glitch/store';

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
});

export const InlineComposeModal: React.FC<{
  onClose: () => void;
}> = ({ onClose }) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();

  useEffect(() => {
    dispatch(mountCompose());
    return () => {
      dispatch(unmountCompose());
    };
  }, [dispatch]);

  const handleSubmitSuccess = useCallback(() => {
    onClose();
  }, [onClose]);

  return (
    <div className='modal-root__modal inline-compose-modal'>
      <div className='inline-compose-modal__header'>
        <h1>
          <FormattedMessage id='status.reply' defaultMessage='Reply' />
        </h1>
        <IconButton
          title={intl.formatMessage(messages.close)}
          icon='close'
          iconComponent={CloseIcon}
          onClick={onClose}
        />
      </div>

      <div className='inline-compose-modal__body'>
        <ComposeFormContainer
          isInline
          withoutNavigation
          onSubmitSuccess={handleSubmitSuccess}
        />
      </div>
    </div>
  );
};
