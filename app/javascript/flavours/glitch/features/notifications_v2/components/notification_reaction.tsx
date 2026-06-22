import { useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import AddReactionIcon from '@/material-icons/400-24px/add_reaction.svg?react';
import { unicodeHexToUrl } from 'flavours/glitch/features/emoji/normalize';
import { emojiToUnicodeHex } from 'flavours/glitch/features/emoji/utils';
import { autoPlayGif } from 'flavours/glitch/initial_state';
import type { NotificationGroupReaction } from 'flavours/glitch/models/notification_group';
import { assetHost } from 'flavours/glitch/utils/config';

import type { LabelRenderer } from './notification_group_with_status';
import { NotificationWithStatus } from './notification_with_status';

const ReactionEmoji: React.FC<{
  name: string;
  url?: string;
  staticUrl?: string;
}> = ({ name, url, staticUrl }) => {
  if (url) {
    return (
      <img
        draggable='false'
        className='emojione custom-emoji'
        alt={`:${name}:`}
        src={autoPlayGif ? url : (staticUrl ?? url)}
      />
    );
  }

  return (
    <img
      draggable='false'
      className='emojione'
      alt={name}
      src={unicodeHexToUrl({ unicodeHex: emojiToUnicodeHex(name), assetHost })}
    />
  );
};

export const NotificationReaction: React.FC<{
  notification: NotificationGroupReaction;
  unread: boolean;
}> = ({ notification, unread }) => {
  const { reaction } = notification;

  const labelRenderer: LabelRenderer = useCallback(
    (displayedName) =>
      reaction ? (
        <FormattedMessage
          id='notification.reaction_with_emoji'
          defaultMessage='{name} reacted with {emoji} to your post'
          values={{
            name: displayedName,
            emoji: (
              <ReactionEmoji
                name={reaction.name}
                url={reaction.url}
                staticUrl={reaction.static_url}
              />
            ),
          }}
        />
      ) : (
        <FormattedMessage
          id='notification.reaction'
          defaultMessage='{name} reacted to your post'
          values={{ name: displayedName }}
        />
      ),
    [reaction],
  );

  return (
    <NotificationWithStatus
      type='reaction'
      icon={AddReactionIcon}
      iconId='edit'
      accountIds={notification.sampleAccountIds}
      count={notification.notifications_count}
      statusId={notification.statusId}
      labelRenderer={labelRenderer}
      unread={unread}
      collapsed
    />
  );
};
