import { useCallback } from 'react';

import { useIntl, defineMessages } from 'react-intl';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import SwitchAccountIcon from '@/material-icons/400-24px/switch_account.svg?react';
import { cancelReplyCompose } from 'mastodon/actions/compose';
import { openModal } from 'mastodon/actions/modal';
import { Account } from 'mastodon/components/account';
import { IconButton } from 'mastodon/components/icon_button';
import { me } from 'mastodon/initial_state';
import { useAppDispatch, useAppSelector } from 'mastodon/store';

const messages = defineMessages({
  cancel: { id: 'reply_indicator.cancel', defaultMessage: 'Cancel' },
  switchAccount: {
    id: 'navigation_bar.switch_account',
    defaultMessage: 'Switch account',
  },
});

export const NavigationBar: React.FC = () => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const isReplying = useAppSelector(
    (state) => !!state.compose.get('in_reply_to'),
  );

  const handleCancelClick = useCallback(() => {
    dispatch(cancelReplyCompose());
  }, [dispatch]);

  const handleSwitchAccountClick = useCallback(() => {
    dispatch(openModal({ modalType: 'ACCOUNT_SWITCHER', modalProps: {} }));
  }, [dispatch]);

  if (!me) {
    return null;
  }

  return (
    <div className='navigation-bar'>
      <Account id={me} minimal />

      <div className='navigation-bar__actions'>
        <IconButton
          title={intl.formatMessage(messages.switchAccount)}
          icon=''
          iconComponent={SwitchAccountIcon}
          onClick={handleSwitchAccountClick}
          className='navigation-bar__switch-account'
        />

        {isReplying && (
          <IconButton
            title={intl.formatMessage(messages.cancel)}
            icon=''
            iconComponent={CloseIcon}
            onClick={handleCancelClick}
          />
        )}
      </div>
    </div>
  );
};
