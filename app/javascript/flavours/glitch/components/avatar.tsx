import { useState, useCallback } from 'react';

import classNames from 'classnames';
import { Link } from 'react-router-dom';

import { useHovering } from 'flavours/glitch/hooks/useHovering';
import {
  autoPlayGif,
  avatarDecorationsEnabled,
  forceRoundAvatarDecoration,
  me,
  showAvatarDecorations,
  showFederatedAvatarDecorations,
} from 'flavours/glitch/initial_state';
import type { Account } from 'flavours/glitch/models/account';

import { useAccount } from '../hooks/useAccount';

import { buildDecorationTransform } from './avatar_decoration_utils';

interface Props {
  account:
    | (Pick<Account, 'id' | 'acct' | 'avatar' | 'avatar_static'> & {
        avatar_decorations?: Account['avatar_decorations'];
      })
    | undefined; // FIXME: remove `undefined` once we know for sure its always there
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

  const isRemote = account?.acct.includes('@') ?? false;
  const decorations = account?.avatar_decorations;
  const isGuest = !me;
  const visibleDecorations =
    avatarDecorationsEnabled &&
    (forceShowDecorations || isGuest || showAvatarDecorations) &&
    (!isRemote || isGuest || showFederatedAvatarDecorations) &&
    decorations?.length
      ? decorations
      : [];

  const hasDecoration = visibleDecorations.length > 0;

  const avatar = (
    <span
      className={classNames(className, 'account__avatar', {
        'account__avatar--inline': inline,
        'account__avatar--loading': loading,
        'account__avatar--decorated': hasDecoration,
        'account__avatar--force-round':
          hasDecoration && forceRoundAvatarDecoration,
      })}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      style={style}
      data-avatar-of={account && `@${account.acct}`}
    >
      {src && !error && (
        <img src={src} alt={alt} onLoad={handleLoad} onError={handleError} />
      )}

      {visibleDecorations.map((decoration, index) => (
        <img
          key={`${decoration.id}-${index}`}
          className='account__avatar__decoration'
          src={animate || hovering ? decoration.url : decoration.static_url}
          alt=''
          aria-hidden='true'
          style={{
            transform: buildDecorationTransform(decoration),
            opacity: decoration.opacity,
          }}
        />
      ))}

      {counter && (
        <span
          className='account__avatar__counter'
          style={{ borderColor: counterBorderColor }}
        >
          {counter}
        </span>
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
