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
import { useAppSelector } from 'flavours/glitch/store';

import { AvatarDecoration } from '../../components/avatar_decoration';
import { catEffectsVisibleFor } from '../nyaify';

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
  is_cat?: boolean;
}

type AvatarDecorationAccount = Pick<Account | AccountShapeFull, 'acct'> &
  SharlayanAvatarAccountFields;

interface Options {
  account?: AvatarDecorationAccount;
  forceShowDecorations?: boolean;
  animate?: boolean;
  hovering: boolean;
  src?: string;
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

export function sharlayanShowsCatEars(
  account: AvatarDecorationAccount | undefined,
): boolean {
  return catEffectsVisibleFor(account?.acct, account?.is_cat);
}

export function useSharlayanAvatarExtras({
  account,
  forceShowDecorations = false,
  animate,
  hovering,
  src,
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

  const showCatEars = sharlayanShowsCatEars(account);

  const decorationClassNames = {
    'account__avatar--decorated': hasDecorations,
    'account__avatar--cat': showCatEars,
    'account__avatar--force-round':
      hasDecorations && avatarDecorationShape === 'round',
    'account__avatar--force-square':
      hasDecorations && avatarDecorationShape === 'square',
  };

  const avatarExtras = (
    <>
      {showCatEars && (
        <span className='account__avatar__cat-ears' aria-hidden='true'>
          <span
            className='account__avatar__cat-ears__ear account__avatar__cat-ears__ear--left'
            style={src ? { backgroundImage: `url(${src})` } : undefined}
          />
          <span
            className='account__avatar__cat-ears__ear account__avatar__cat-ears__ear--right'
            style={src ? { backgroundImage: `url(${src})` } : undefined}
          />
        </span>
      )}

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
