import type { Account, AccountShapeFull } from 'flavours/glitch/models/account';

import { Avatar } from './avatar';

type AvatarAccount = Pick<
  Account | AccountShapeFull,
  'id' | 'acct' | 'avatar' | 'avatar_static' | 'avatar_decorations'
>;

interface Props {
  account?: AvatarAccount;
  friend?: AvatarAccount;
  size?: number;
  baseSize?: number;
  overlaySize?: number;
}

export const AvatarOverlay: React.FC<Props> = ({
  account,
  friend,
  size = 46,
  baseSize = 36,
  overlaySize = 24,
}) => {
  return (
    <div
      className='account__avatar-overlay'
      style={{ width: size, height: size }}
    >
      <div className='account__avatar-overlay-base'>
        <Avatar account={account} size={baseSize} />
      </div>
      <div className='account__avatar-overlay-overlay'>
        <Avatar account={friend} size={overlaySize} />
      </div>
    </div>
  );
};
