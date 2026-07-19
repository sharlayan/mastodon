import classNames from 'classnames';

import {
  avatarDecorationShape,
  avatarDecorationsEnabled,
  me,
  showAvatarDecorations,
  showFederatedAvatarDecorations,
} from 'flavours/glitch/initial_state';
import type { Account } from 'flavours/glitch/models/account';

import { buildDecorationTransform } from './avatar_decoration_utils';

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

  if (!visibleDecorations.length) return null;

  return (
    <div
      className={classNames('account__avatar__decoration-layer', {
        'account__avatar__decoration-layer--force-round':
          avatarDecorationShape === 'round',
        'account__avatar__decoration-layer--force-square':
          avatarDecorationShape === 'square',
      })}
      aria-hidden='true'
    >
      {visibleDecorations.map((decoration, index) => (
        <img
          key={`${decoration.id}-${index}`}
          className='account__avatar__decoration'
          src={animate || hovering ? decoration.url : decoration.static_url}
          alt=''
          style={{
            transform: buildDecorationTransform(decoration),
            opacity: decoration.opacity,
          }}
        />
      ))}
    </div>
  );
};
