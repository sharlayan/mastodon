import { useState, useCallback } from 'react';

import classNames from 'classnames';
import { Link } from 'react-router-dom';

import { useHovering } from 'flavours/glitch/hooks/useHovering';
import { autoPlayGif } from 'flavours/glitch/initial_state';
import type { Account, AccountShapeFull } from 'flavours/glitch/models/account';
import type { SharlayanAvatarAccountFields } from 'flavours/glitch/sharlayan/account/avatar';
import { useSharlayanAvatarExtras } from 'flavours/glitch/sharlayan/account/avatar';

import { useAccount } from '../hooks/useAccount';

import { RetryingImage } from './retrying_image';

interface Props {
  account?: Pick<
    Account | AccountShapeFull,
    'id' | 'acct' | 'avatar' | 'avatar_static'
  > &
    SharlayanAvatarAccountFields;
  alt?: string;
  size?: number | null;
  style?: React.CSSProperties;
  inline?: boolean;
  animate?: boolean;
  withLink?: boolean;
  counter?: number | string;
  counterBorderColor?: string;
  className?: string;
  forceShowDecorations?: boolean;
  showOnlineStatus?: boolean;
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
  showOnlineStatus = false,
}) => {
  const { hovering, handleMouseEnter, handleMouseLeave } = useHovering(animate);
  const [loading, setLoading] = useState(true);

  const style =
    size !== null
      ? {
          ...styleFromParent,
          width: `${size}px`,
          height: `${size}px`,
        }
      : styleFromParent;

  const src = hovering || animate ? account?.avatar : account?.avatar_static;

  const handleLoad = useCallback(() => {
    setLoading(false);
  }, [setLoading]);

  const { decorationClassNames, avatarExtras } = useSharlayanAvatarExtras({
    account,
    forceShowDecorations,
    showOnlineStatus,
    animate,
    hovering,
  });

  const avatar = (
    <span
      className={classNames(className, 'account__avatar', {
        'account__avatar--inline': inline,
        'account__avatar--loading': loading,
        ...decorationClassNames,
      })}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      style={style}
      data-avatar-of={account && `@${account.acct}`}
    >
      {src && <RetryingImage src={src} alt={alt} onLoad={handleLoad} />}

      {avatarExtras}

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
