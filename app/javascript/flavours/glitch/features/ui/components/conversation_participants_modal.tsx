import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import { Account } from 'flavours/glitch/components/account';
import { IconButton } from 'flavours/glitch/components/icon_button';

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
});

export const ConversationParticipantsModal: React.FC<{
  accountIds: string[];
  onClose: () => void;
}> = ({ accountIds, onClose }) => {
  const intl = useIntl();

  return (
    <div className='modal-root__modal conversation-participants-modal'>
      <div className='conversation-participants-modal__header'>
        <h1>
          <FormattedMessage
            id='conversation.participants'
            defaultMessage='Participants'
          />
        </h1>

        <IconButton
          className='conversation-participants-modal__close'
          title={intl.formatMessage(messages.close)}
          icon='close'
          iconComponent={CloseIcon}
          onClick={onClose}
        />
      </div>

      <div className='conversation-participants-modal__list'>
        {accountIds.map((accountId) => (
          <Account key={accountId} id={accountId} minimal />
        ))}
      </div>
    </div>
  );
};
