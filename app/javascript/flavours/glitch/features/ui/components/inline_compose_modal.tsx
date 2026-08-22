import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
} from 'react';

import { FormattedMessage, defineMessages, useIntl } from 'react-intl';

import { useHistory } from 'react-router-dom';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import {
  discardCompose,
  mountCompose,
  unmountCompose,
} from 'flavours/glitch/actions/compose';
import { apiRequest } from 'flavours/glitch/api';
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
  {
    onClose: () => void;
    title?: 'compose' | 'reply' | 'direct';
    navigateToConversation?: boolean;
    discardOnClose?: boolean;
  }
>(
  (
    {
      onClose,
      title = 'reply',
      navigateToConversation = false,
      discardOnClose = true,
    },
    ref,
  ) => {
    const dispatch = useAppDispatch();
    const history = useHistory();
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
          if (!submitted.current && discardOnClose) {
            dispatch(discardCompose());
          }
        },
      }),
      [discardOnClose, dispatch],
    );

    const handleSubmitSuccess = useCallback(
      (status: { id?: string }) => {
        submitted.current = true;
        onClose();

        if (navigateToConversation && status.id) {
          void apiRequest<{ id: string | null }>(
            'GET',
            `v1/conversations/with_status/${status.id}`,
          )
            .then(({ id }) => {
              if (id) {
                history.push(`/conversations/${id}`);
              }
            })
            .catch(() => undefined);
        }
      },
      [history, navigateToConversation, onClose],
    );

    return (
      <div className='modal-root__modal inline-compose-modal'>
        <div className='inline-compose-modal__header'>
          <h1>
            {title === 'direct' ? (
              <FormattedMessage
                id='account.menu.direct'
                defaultMessage='Privately mention'
              />
            ) : title === 'compose' ? (
              <FormattedMessage
                id='tabs_bar.publish'
                defaultMessage='New Post'
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
  },
);

InlineComposeModal.displayName = 'InlineComposeModal';
