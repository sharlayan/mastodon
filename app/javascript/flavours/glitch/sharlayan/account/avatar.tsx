import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import type { ApiOnlineStatus } from 'flavours/glitch/api_types/accounts';
import {
  avatarDecorationShape,
  avatarDecorationsEnabled,
  me,
  showAvatarDecorations,
  showFederatedAvatarDecorations,
} from 'flavours/glitch/initial_state';
import type { Account, AccountShapeFull } from 'flavours/glitch/models/account';
import { forceRoundAvatar } from 'flavours/glitch/sharlayan/roleplay';
import { useAppSelector } from 'flavours/glitch/store';

import { AvatarDecoration } from '../../components/avatar_decoration';

const messages = defineMessages({
  online: { id: 'account.online_status.online', defaultMessage: 'Online' },
  active: {
    id: 'account.online_status.active',
    defaultMessage: 'Recently active',
  },
  offline: { id: 'account.online_status.offline', defaultMessage: 'Offline' },
});

export interface SharlayanAvatarAccountFields {
  avatar_decorations?: Account['avatar_decorations'];
  online_status?: ApiOnlineStatus;
}

type AvatarDecorationAccount = Pick<Account | AccountShapeFull, 'acct'> &
  SharlayanAvatarAccountFields;

interface Options {
  account?: AvatarDecorationAccount;
  forceShowDecorations?: boolean;
  animate?: boolean;
  hovering: boolean;
}

export function sharlayanHasAvatarDecorations(
  account: AvatarDecorationAccount | undefined,
  forceShow = false,
): boolean {
  const isRemote = account?.acct.includes('@') ?? false;
  const isGuest = !me;

  return Boolean(
    avatarDecorationsEnabled &&
    (forceShow || isGuest || showAvatarDecorations) &&
    (!isRemote || isGuest || showFederatedAvatarDecorations) &&
    (account?.avatar_decorations?.length ?? 0) > 0,
  );
}

export function useSharlayanAvatarExtras({
  account,
  forceShowDecorations = false,
  animate,
  hovering,
}: Options) {
  const intl = useIntl();

  const showOthersOnlineStatus = useAppSelector(
    (state) =>
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access
      state.local_settings.getIn(
        ['show_others_online_status'],
        false,
      ) as boolean,
  );
  const onlineStatus = account?.online_status;
  const showOnlineStatus =
    showOthersOnlineStatus &&
    (onlineStatus === 'online' ||
      onlineStatus === 'active' ||
      onlineStatus === 'offline');

  const hasDecorations = sharlayanHasAvatarDecorations(
    account,
    forceShowDecorations,
  );

  const decorationClassNames = {
    'account__avatar--decorated': hasDecorations,
    'account__avatar--force-round':
      forceRoundAvatar || (hasDecorations && avatarDecorationShape === 'round'),
    'account__avatar--force-square':
      !forceRoundAvatar && hasDecorations && avatarDecorationShape === 'square',
  };

  const avatarExtras = (
    <>
      <AvatarDecoration
        account={account}
        animate={animate ?? false}
        hovering={hovering}
        forceShow={forceShowDecorations}
      />

      {showOnlineStatus && (
        <span
          className={classNames(
            'account__avatar__online',
            `account__avatar__online--${onlineStatus}`,
          )}
          title={intl.formatMessage(messages[onlineStatus])}
        />
      )}
    </>
  );

  return { decorationClassNames, avatarExtras };
}
