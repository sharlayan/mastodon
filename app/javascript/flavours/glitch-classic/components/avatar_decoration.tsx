import { useEffect, useRef, useState } from 'react';

import classNames from 'classnames';

import {
  avatarDecorationShape,
  avatarDecorationsEnabled,
  forceRoundAvatar,
  me,
  showAvatarDecorations,
  showFederatedAvatarDecorations,
} from 'flavours/glitch-classic/initial_state';
import type { Account } from 'flavours/glitch-classic/models/account';

import {
  FrozenDecorationImage,
  useDecorationAutoplayDisabled,
} from './avatar_decoration_image';
import { buildDecorationTransform } from './avatar_decoration_utils';
import { RetryingImage } from './retrying_image';

interface Props {
  account:
    | (Pick<Account, 'acct'> & {
        avatar_decorations?: Account['avatar_decorations'];
      })
    | undefined;
  animate: boolean;
  hovering?: boolean;
  forceShow?: boolean;
}

export const AvatarDecoration: React.FC<Props> = ({
  account,
  animate,
  hovering = false,
  forceShow = false,
}) => {
  const isRemote = account?.acct.includes('@') ?? false;
  const decorations = account?.avatar_decorations;
  const isGuest = !me;

  const visibleDecorations =
    avatarDecorationsEnabled &&
    (forceShow || isGuest || showAvatarDecorations) &&
    (!isRemote || isGuest || showFederatedAvatarDecorations) &&
    decorations?.length
      ? decorations
      : [];

  const hasVisibleDecorations = visibleDecorations.length > 0;
  const autoplayDisabled = useDecorationAutoplayDisabled();
  const layerRef = useRef<HTMLDivElement>(null);
  const [pointerOver, setPointerOver] = useState(false);

  useEffect(() => {
    if (!autoplayDisabled || !hasVisibleDecorations) return undefined;
    const avatar = layerRef.current?.closest('.account__avatar');
    if (!avatar) return undefined;

    const handleEnter = () => {
      setPointerOver(true);
    };
    const handleLeave = () => {
      setPointerOver(false);
    };
    avatar.addEventListener('mouseenter', handleEnter);
    avatar.addEventListener('mouseleave', handleLeave);
    return () => {
      avatar.removeEventListener('mouseenter', handleEnter);
      avatar.removeEventListener('mouseleave', handleLeave);
    };
  }, [autoplayDisabled, hasVisibleDecorations]);

  if (!hasVisibleDecorations) return null;

  return (
    <div
      ref={layerRef}
      className={classNames('account__avatar__decoration-layer', {
        'account__avatar__decoration-layer--force-round':
          forceRoundAvatar || avatarDecorationShape === 'round',
        'account__avatar__decoration-layer--force-square':
          !forceRoundAvatar && avatarDecorationShape === 'square',
      })}
      aria-hidden='true'
    >
      {visibleDecorations.map((decoration, index) => {
        const style = {
          transform: buildDecorationTransform(decoration),
          opacity: decoration.opacity,
        };
        return autoplayDisabled ? (
          <FrozenDecorationImage
            key={`${decoration.id}-${index}`}
            className='account__avatar__decoration'
            url={decoration.url}
            staticUrl={decoration.static_url}
            playing={pointerOver}
            style={style}
          />
        ) : (
          <RetryingImage
            key={`${decoration.id}-${index}`}
            className='account__avatar__decoration'
            src={animate || hovering ? decoration.url : decoration.static_url}
            alt=''
            style={style}
          />
        );
      })}
    </div>
  );
};
