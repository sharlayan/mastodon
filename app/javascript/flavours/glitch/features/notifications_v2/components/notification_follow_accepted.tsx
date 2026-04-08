import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import PersonAddIcon from '@/material-icons/400-24px/person_add-fill.svg?react';
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

  const additionalContent = notification.followMessage ? (
    <div className='notification__follow-message'>
      {notification.followMessage}
    </div>
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
