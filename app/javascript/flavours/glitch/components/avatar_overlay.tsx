import type { Account } from 'flavours/glitch/models/account';

import { Avatar } from './avatar';

interface Props {
  account: Account | undefined; // FIXME: remove `undefined` once we know for sure its always there
  friend: Account | undefined; // FIXME: remove `undefined` once we know for sure its always there
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
