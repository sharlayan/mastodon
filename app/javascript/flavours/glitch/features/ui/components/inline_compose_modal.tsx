import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
} from 'react';

import { FormattedMessage, defineMessages, useIntl } from 'react-intl';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import {
  discardCompose,
  mountCompose,
  unmountCompose,
} from 'flavours/glitch/actions/compose';
import { IconButton } from 'flavours/glitch/components/icon_button';
import ComposeFormContainer from 'flavours/glitch/features/compose/containers/compose_form_container';
import { useAppDispatch } from 'flavours/glitch/store';

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
});

export interface InlineComposeModalRef {
  onModalClose: () => void;
}

export const InlineComposeModal = forwardRef<
  InlineComposeModalRef,
  { onClose: () => void; title?: 'reply' | 'direct' }
>(({ onClose, title = 'reply' }, ref) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const submitted = useRef(false);

  useEffect(() => {
    dispatch(mountCompose());
    return () => {
      dispatch(unmountCompose());
    };
  }, [dispatch]);

  useImperativeHandle(
    ref,
    () => ({
      onModalClose: () => {
        if (!submitted.current) {
          dispatch(discardCompose());
        }
      },
    }),
    [dispatch],
  );

  const handleSubmitSuccess = useCallback(() => {
    submitted.current = true;
    onClose();
  }, [onClose]);

  return (
    <div className='modal-root__modal inline-compose-modal'>
      <div className='inline-compose-modal__header'>
        <h1>
          {title === 'direct' ? (
            <FormattedMessage
              id='account.menu.direct'
              defaultMessage='Privately mention'
            />
          ) : (
            <FormattedMessage id='status.reply' defaultMessage='Reply' />
          )}
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
});

InlineComposeModal.displayName = 'InlineComposeModal';
