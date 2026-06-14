import { useCallback } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { MfmRenderer } from 'flavours/glitch/components/mfm';
import { useCustomEmojis } from 'flavours/glitch/hooks/useCustomEmojis';

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
});

export const MfmPreviewModal: React.FC<{
  text: string;
  onClose: () => void;
}> = ({ text, onClose }) => {
  const intl = useIntl();
  const customEmojis = useCustomEmojis();

  const handleClose = useCallback(() => {
    onClose();
  }, [onClose]);

  return (
    <div className='modal-root__modal mfm-preview-modal'>
      <div className='mfm-preview-modal__header'>
        <div className='mfm-preview-modal__header__title'>
          <h1>
            <FormattedMessage
              id='mfm_preview_modal.title'
              defaultMessage='MFM preview'
            />
          </h1>
        </div>

        <IconButton
          className='mfm-preview-modal__close'
          title={intl.formatMessage(messages.close)}
          icon='close'
          iconComponent={CloseIcon}
          onClick={handleClose}
        />
      </div>

      <div className='mfm-preview-modal__body'>
        {text.trim().length > 0 ? (
          <MfmRenderer text={text} emojis={customEmojis} animationsEnabled />
        ) : (
          <div className='mfm-preview-modal__empty'>
            <FormattedMessage
              id='mfm_preview_modal.empty'
              defaultMessage='Nothing to preview yet.'
            />
          </div>
        )}
      </div>
    </div>
  );
};
