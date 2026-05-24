import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import escapeTextContentForBrowser from 'escape-html';

import PersonAddIcon from '@/material-icons/400-24px/person_add-fill.svg?react';
import { EmojiHTML } from 'flavours/glitch/components/emoji/html';
import { me } from 'flavours/glitch/initial_state';
import type { NotificationGroupFollowAccepted } from 'flavours/glitch/models/notification_group';
import { useAppSelector } from 'flavours/glitch/store';

import type { LabelRenderer } from './notification_group_with_status';
import { NotificationGroupWithStatus } from './notification_group_with_status';

const labelRenderer: LabelRenderer = (displayedName, total, seeMoreHref) => {
  if (total === 1)
    return (
      <FormattedMessage
        id='notification.follow_accepted'
        defaultMessage='{name} accepted your follow'
        values={{ name: displayedName }}
      />
    );

  return (
    <FormattedMessage
      id='notification.follow_accepted.name_and_others'
      defaultMessage='{name} and <a>{count, plural, one {# other} other {# others}}</a> accepted your follow'
      values={{
        name: displayedName,
        count: total - 1,
        a: (chunks) =>
          seeMoreHref ? <Link to={seeMoreHref}>{chunks}</Link> : chunks,
      }}
    />
  );
};

export const NotificationFollowAccepted: React.FC<{
  notification: NotificationGroupFollowAccepted;
  unread: boolean;
}> = ({ notification, unread }) => {
  const username = useAppSelector(
    (state) => state.accounts.getIn([me, 'username']) as string,
  );
  const sourceAccountId = notification.sampleAccountIds[0];
  const sourceEmojis = useAppSelector((state) =>
    sourceAccountId ? state.accounts.get(sourceAccountId)?.emojis : undefined,
  );

  const additionalContent = notification.followMessage ? (
    <EmojiHTML
      className='notification__follow-message'
      htmlString={escapeTextContentForBrowser(notification.followMessage)}
      extraEmojis={sourceEmojis}
    />
  ) : undefined;

  return (
    <NotificationGroupWithStatus
      type='follow_accepted'
      icon={PersonAddIcon}
      iconId='person-add'
      accountIds={notification.sampleAccountIds}
      timestamp={notification.latest_page_notification_at}
      count={notification.notifications_count}
      labelRenderer={labelRenderer}
      labelSeeMoreHref={`/@${username}/following`}
      unread={unread}
      additionalContent={additionalContent}
    />
  );
};
