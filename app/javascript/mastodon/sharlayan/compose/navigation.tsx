import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import SwitchAccountIcon from '@/material-icons/400-24px/switch_account.svg?react';
import { openModal } from 'mastodon/actions/modal';
import { IconButton } from 'mastodon/components/icon_button';
import { useAppDispatch } from 'mastodon/store';

const messages = defineMessages({
  switchAccount: {
    id: 'navigation_bar.switch_account',
    defaultMessage: 'Switch account',
  },
});

export const accountSwitcherModal = {
  modalType: 'ACCOUNT_SWITCHER',
  modalProps: {},
} as const;

export const SharlayanComposeNavigation = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const handleSwitchAccountClick = useCallback(() => {
    dispatch(openModal(accountSwitcherModal));
  }, [dispatch]);

  return (
    <IconButton
      title={intl.formatMessage(messages.switchAccount)}
      icon=''
      iconComponent={SwitchAccountIcon}
      onClick={handleSwitchAccountClick}
      className='navigation-bar__switch-account'
    />
  );
};
