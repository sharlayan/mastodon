import { useState, useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link } from 'react-router-dom';

import type { ApiOnlineStatus } from 'flavours/glitch/api_types/accounts';
import { useHovering } from 'flavours/glitch/hooks/useHovering';
import {
  autoPlayGif,
  avatarDecorationShape,
  avatarDecorationsEnabled,
  me,
  showAvatarDecorations,
  showFederatedAvatarDecorations,
} from 'flavours/glitch/initial_state';
import type { Account, AccountShapeFull } from 'flavours/glitch/models/account';
import { forceRoundAvatar } from 'flavours/glitch/sharlayan/roleplay';
import { useAppSelector } from 'flavours/glitch/store';

import { useAccount } from '../hooks/useAccount';

import { AvatarDecoration } from './avatar_decoration';

const messages = defineMessages({
  online: { id: 'account.online_status.online', defaultMessage: 'Online' },
  active: {
    id: 'account.online_status.active',
    defaultMessage: 'Recently active',
  },
  offline: { id: 'account.online_status.offline', defaultMessage: 'Offline' },
});

interface Props {
  account?: Pick<
    Account | AccountShapeFull,
    'id' | 'acct' | 'avatar' | 'avatar_static'
  > & {
    avatar_decorations?: Account['avatar_decorations'];
    online_status?: ApiOnlineStatus;
  };
  alt?: string;
  size?: number;
  style?: React.CSSProperties;
  inline?: boolean;
  animate?: boolean;
  withLink?: boolean;
  counter?: number | string;
  counterBorderColor?: string;
  className?: string;
  forceShowDecorations?: boolean;
}

export const Avatar: React.FC<Props> = ({
  account,
  alt = '',
  animate = autoPlayGif,
  size = 20,
  inline = false,
  withLink = false,
  style: styleFromParent,
  className,
  counter,
  counterBorderColor,
  forceShowDecorations = false,
}) => {
  const intl = useIntl();
  const { hovering, handleMouseEnter, handleMouseLeave } = useHovering(animate);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const style = {
    ...styleFromParent,
    width: `${size}px`,
    height: `${size}px`,
  };

  const src = hovering || animate ? account?.avatar : account?.avatar_static;

  const handleLoad = useCallback(() => {
    setLoading(false);
  }, [setLoading]);

  const handleError = useCallback(() => {
    setError(true);
  }, [setError]);

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

  const isRemote = account?.acct.includes('@') ?? false;
  const isGuest = !me;
  const hasDecorations =
    avatarDecorationsEnabled &&
    (forceShowDecorations || isGuest || showAvatarDecorations) &&
    (!isRemote || isGuest || showFederatedAvatarDecorations) &&
    (account?.avatar_decorations?.length ?? 0) > 0;

  const avatar = (
    <span
      className={classNames(className, 'account__avatar', {
        'account__avatar--inline': inline,
        'account__avatar--loading': loading,
        'account__avatar--decorated': hasDecorations,
        'account__avatar--force-round':
          forceRoundAvatar ||
          (hasDecorations && avatarDecorationShape === 'round'),
        'account__avatar--force-square':
          !forceRoundAvatar &&
          hasDecorations &&
          avatarDecorationShape === 'square',
      })}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      style={style}
      data-avatar-of={account && `@${account.acct}`}
    >
      {src && !error && (
        <img src={src} alt={alt} onLoad={handleLoad} onError={handleError} />
      )}

      <AvatarDecoration
        account={account}
        animate={animate ?? false}
        hovering={hovering}
        forceShow={forceShowDecorations}
      />

      {counter && (
        <span
          className='account__avatar__counter'
          style={{ borderColor: counterBorderColor }}
        >
          {counter}
        </span>
      )}

      {showOnlineStatus && (
        <span
          className={classNames(
            'account__avatar__online',
            `account__avatar__online--${onlineStatus}`,
          )}
          title={intl.formatMessage(messages[onlineStatus])}
        />
      )}
    </span>
  );

  if (withLink) {
    return (
      <Link
        to={`/@${account?.acct}`}
        title={`@${account?.acct}`}
        data-hover-card-account={account?.id}
      >
        {avatar}
      </Link>
    );
  }

  return avatar;
};

export const AvatarById: React.FC<
  { accountId: string | undefined } & Omit<Props, 'account'>
> = ({ accountId, ...otherProps }) => {
  const account = useAccount(accountId);
  return <Avatar account={account} {...otherProps} />;
};
