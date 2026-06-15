import { FormattedMessage } from 'react-intl';

import AddReactionIcon from '@/material-icons/400-24px/add_reaction.svg?react';
import type { NotificationGroupReaction } from 'flavours/glitch/models/notification_group';

import type { LabelRenderer } from './notification_group_with_status';
import { NotificationWithStatus } from './notification_with_status';

const labelRenderer: LabelRenderer = (displayedName) => (
  <FormattedMessage
    id='notification.reaction'
    defaultMessage='{name} reacted to your post'
    values={{ name: displayedName }}
  />
);

export const NotificationReaction: React.FC<{
  notification: NotificationGroupReaction;
  unread: boolean;
}> = ({ notification, unread }) => (
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
