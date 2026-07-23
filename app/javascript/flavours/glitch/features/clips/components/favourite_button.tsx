import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import StarIcon from '@/material-icons/400-24px/star-fill.svg?react';
import StarBorderIcon from '@/material-icons/400-24px/star.svg?react';
import { favouriteClip, unfavouriteClip } from 'flavours/glitch/actions/clips';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { useIdentity } from 'flavours/glitch/identity_context';
import type { Clip } from 'flavours/glitch/models/clip';
import { useAppDispatch } from 'flavours/glitch/store';

const messages = defineMessages({
  favourite: { id: 'clips.favourite', defaultMessage: 'Favorite clip' },
  unfavourite: {
    id: 'clips.unfavourite',
    defaultMessage: 'Remove clip from favorites',
  },
});

export const ClipFavouriteButton: React.FC<{
  clip: Clip;
  className?: string;
}> = ({ clip, className }) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const { signedIn } = useIdentity();

  const handleClick = useCallback(() => {
    void dispatch(
      clip.favourited
        ? unfavouriteClip({ id: clip.id })
        : favouriteClip({ id: clip.id }),
    );
  }, [clip.favourited, clip.id, dispatch]);

  return (
    <IconButton
      className={className}
      icon='star'
      iconComponent={clip.favourited ? StarIcon : StarBorderIcon}
      title={intl.formatMessage(
        clip.favourited ? messages.unfavourite : messages.favourite,
      )}
      active={clip.favourited}
      animate
      counter={clip.favourites_count}
      disabled={!signedIn}
      onClick={handleClick}
    />
  );
};
