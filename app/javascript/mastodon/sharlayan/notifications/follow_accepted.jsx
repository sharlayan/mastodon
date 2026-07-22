import PropTypes from 'prop-types';

import { FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';
import ImmutablePropTypes from 'react-immutable-proptypes';

import PersonAddIcon from '@/material-icons/400-24px/person_add-fill.svg?react';
import { Account } from 'mastodon/components/account';
import { Hotkeys } from 'mastodon/components/hotkeys';
import { Icon } from 'mastodon/components/icon';

export const SharlayanFollowAcceptedNotification = ({ account, handlers, hidden, link, notification, unread }) => {
  const intl = useIntl();
  const message = intl.formatMessage({ id: 'notification.follow_accepted', defaultMessage: '{name} accepted your follow' }, { name: account.get('acct') });
  const timestamp = notification.get('created_at');
  const ariaLabel = [message, intl.formatDate(timestamp, { hour: '2-digit', minute: '2-digit', month: 'short', day: 'numeric' })].join(', ');
  const followMessage = notification.get('follow_message');

  return (
    <Hotkeys handlers={handlers}>
      <div className={classNames('notification notification-follow-accepted focusable', { unread })} tabIndex={0} aria-label={ariaLabel}>
        <div className='notification__message'>
          <Icon id='user-plus' icon={PersonAddIcon} />

          <span title={timestamp}>
            <FormattedMessage id='notification.follow_accepted' defaultMessage='{name} accepted your follow' values={{ name: link }} />
          </span>
        </div>

        <Account id={account.get('id')} hidden={hidden} />

        {followMessage && <div className='notification__follow-message'>{followMessage}</div>}
      </div>
    </Hotkeys>
  );
};

SharlayanFollowAcceptedNotification.propTypes = {
  account: ImmutablePropTypes.map.isRequired,
  handlers: PropTypes.object.isRequired,
  hidden: PropTypes.bool,
  link: PropTypes.node.isRequired,
  notification: ImmutablePropTypes.map.isRequired,
  unread: PropTypes.bool,
};
