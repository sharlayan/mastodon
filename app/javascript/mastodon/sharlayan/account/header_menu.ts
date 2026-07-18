import type { useIntl } from 'react-intl';
import { defineMessages } from 'react-intl';

import { refetchAccount } from '@/mastodon/actions/accounts';
import type { Account } from '@/mastodon/models/account';
import type { MenuItem } from '@/mastodon/models/dropdown_menu';
import type { AppDispatch } from '@/mastodon/store';
import RefreshIcon from '@/material-icons/400-24px/refresh.svg?react';

const messages = defineMessages({
  refetchProfile: {
    id: 'account.menu.refetch_profile',
    defaultMessage: 'Refresh profile data',
  },
});

interface SharlayanMenuContext {
  account: Account;
  dispatch: AppDispatch;
  intl: ReturnType<typeof useIntl>;
  signedIn: boolean;
  isRemote: boolean;
}

export function sharlayanRefetchProfileItems({
  account,
  dispatch,
  intl,
  signedIn,
  isRemote,
}: SharlayanMenuContext): MenuItem[] {
  if (!isRemote || !signedIn || account.suspended) {
    return [];
  }

  return [
    {
      text: intl.formatMessage(messages.refetchProfile),
      action: () => {
        dispatch(refetchAccount(account.id));
      },
      icon: RefreshIcon,
    },
  ];
}
