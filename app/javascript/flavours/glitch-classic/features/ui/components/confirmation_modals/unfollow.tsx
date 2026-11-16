import { useCallback } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { unfollowAccount } from 'flavours/glitch-classic/actions/accounts';
import type { Account } from 'flavours/glitch-classic/models/account';
import { useAppDispatch } from 'flavours/glitch-classic/store';

import type { BaseConfirmationModalProps } from './confirmation_modal';
import { ConfirmationModal } from './confirmation_modal';

const messages = defineMessages({
  unfollowConfirm: {
    id: 'confirmations.unfollow.confirm',
    defaultMessage: 'Unfollow',
  },
});

export const ConfirmUnfollowModal: React.FC<
  {
    account: Account;
  } & BaseConfirmationModalProps
> = ({ account, onClose }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const onConfirm = useCallback(() => {
    dispatch(unfollowAccount(account.id));
  }, [dispatch, account.id]);

  return (
    <ConfirmationModal
      title={
        <FormattedMessage
          id='confirmations.unfollow.title'
          defaultMessage='Unfollow {name}?'
          values={{ name: `@${account.acct}` }}
        />
      }
      confirm={intl.formatMessage(messages.unfollowConfirm)}
      onConfirm={onConfirm}
      onClose={onClose}
    />
  );
};
