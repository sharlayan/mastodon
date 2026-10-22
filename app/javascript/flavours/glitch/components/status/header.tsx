import { useId } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link } from 'react-router-dom';

import type { Map as ImmutableMap } from 'immutable';

import { useAccount } from '@/flavours/glitch/hooks/useAccount';
import { useCurrentAccountId } from '@/flavours/glitch/hooks/useAccountId';
import { languages } from '@/flavours/glitch/initial_state';
import type { AccountStatusShape } from '@/flavours/glitch/models/status';
import { useAppSelector } from '@/flavours/glitch/store';
import ForumIcon from '@/material-icons/400-24px/forum.svg?react';
import HomeIcon from '@/material-icons/400-24px/home.svg?react';

import { Avatar } from '../avatar';
import { Badge } from '../badge';
import { CollapseButton } from '../collapse_button';
import { DisplayName } from '../display_name';
import { useAccountHandle } from '../display_name/default';
import { Icon } from '../icon';
import InstanceBadge, { isLocalInstanceDomain } from '../instance_badge';
import { RelativeTimestamp } from '../relative_timestamp';
import { Skeleton } from '../skeleton';
import { VisibilityIcon } from '../visibility_icon';

import classes from './header.module.scss';
import type { IconName } from './legacy/media_icon';
import { MediaIcon } from './legacy/media_icon';
import { statusLink } from './utils';

const messages = defineMessages({
  edited: { id: 'status.edited', defaultMessage: 'Edited {date}' },
  localOnly: {
    id: 'status.local_only',
    defaultMessage: 'Only visible from your instance',
  },
  reply: { id: 'status.in_reply_to', defaultMessage: 'This toot is a reply' },
});

interface StatusRedesignHeaderProps {
  status: Pick<
    AccountStatusShape,
    | 'id'
    | 'account'
    | 'created_at'
    | 'edited_at'
    | 'visibility'
    | 'mentions'
    | 'local_only'
    | 'limited_scope'
    | 'instance_metadata'
    | 'collapsed'
    | 'language'
    | 'in_reply_to_id'
    | 'media_attachments'
    | 'card'
    | 'poll'
    | 'rp_hidden'
  >;
  collapsed?: boolean;
  onCollapsedChange?: (value: boolean) => void;
  children?: React.ReactNode;
  className?: string;
}

export const StatusRedesignHeader: React.FC<StatusRedesignHeaderProps> = ({
  status,
  collapsed = status.collapsed ?? false,
  onCollapsedChange,
  children,
  className,
}) => {
  const intl = useIntl();
  const hideHandle = useAppSelector(
    (state) =>
      state.local_settings.get(
        'hide_timeline_account_handle',
        false,
      ) as boolean,
  );
  const showInstance = useAppSelector(
    (state) => state.local_settings.get('show_instance_info', false) as boolean,
  );
  const showLocalInstance = useAppSelector(
    (state) =>
      state.local_settings.get('show_instance_info_local', false) as boolean,
  );
  const account = status.account;
  const handle = useAccountHandle(account);
  const currentAccountId = useCurrentAccountId();
  const firstMentionAccount = useAccount(
    status.mentions.find(({ id }) => id !== currentAccountId)?.id,
  );

  const handleId = useId();
  const accountLinkProps = {
    to: {
      pathname: `/@${account.acct}`,
      state: { reference: 'status' },
    },
    title: `@${account.acct}`,
    'data-id': account.id,
    'data-hover-card-account': account.id,
    'data-hover-card-reference': 'status',
  };

  let displayName = (
    <Link
      {...accountLinkProps}
      className={classes.nameLink}
      aria-describedby={hideHandle ? undefined : handleId}
    >
      <DisplayName account={account} variant='noDomain' />
    </Link>
  );
  if (status.visibility === 'private' && status.limited_scope !== 'circle') {
    displayName = (
      <FormattedMessage
        id='status.header.to_followers'
        defaultMessage='{author} to Followers {count, plural, =0 {} one {+ # other} other {+ # others}}'
        description='Count is # of other people mentioned in the post'
        tagName='span'
        values={{ author: displayName, count: status.mentions.length }}
      />
    );
  } else if (
    status.visibility === 'direct' &&
    status.limited_scope !== 'circle' &&
    status.mentions.length > 0
  ) {
    if (status.account.id === currentAccountId && firstMentionAccount) {
      displayName = (
        <FormattedMessage
          id='status.header.message_from_me'
          defaultMessage='{author} to {name} {count, plural, =0 {} one {+ # other} other {+ # others}}'
          description='DisplayName is the author, count is # of other people mentioned in the post'
          tagName='span'
          values={{
            author: displayName,
            name: (
              <DisplayName account={firstMentionAccount} variant='simple' />
            ),
            // Minus two, as we're removing the current user as well.
            count: Math.max(status.mentions.length - 2, 0),
          }}
        />
      );
    } else {
      displayName = (
        <FormattedMessage
          id='status.header.message_to_me'
          defaultMessage='{author} to You {count, plural, =0 {} one {+ # other} other {+ # others}}'
          description='DisplayName is the author, count is # of other people mentioned in the post'
          tagName='span'
          values={{ author: displayName, count: status.mentions.length - 1 }}
        />
      );
    }
  }

  return (
    <header className={classNames(className, classes.root)}>
      <Link
        {...accountLinkProps}
        role='presentation'
        tabIndex={-1}
        className={classes.avatar}
      >
        <Avatar account={account} size={null} />
      </Link>

      <div>
        <p className={classes.name}>
          {displayName}
          &bull;
          <Link
            to={{
              pathname: statusLink(status),
              state: { reference: 'status' },
            }}
            className={classes.date}
          >
            <RelativeTimestamp timestamp={status.created_at} />
            {status.edited_at && (
              <abbr
                title={intl.formatMessage(messages.edited, {
                  date: intl.formatDate(status.edited_at, {
                    year: 'numeric',
                    month: 'short',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit',
                  }),
                })}
              >
                {' '}
                *
              </abbr>
            )}
          </Link>
        </p>

        {!hideHandle && (
          <p className={classes.handle}>
            <Link
              {...accountLinkProps}
              role='presentation'
              tabIndex={-1}
              id={handleId}
            >
              {handle ?? <Skeleton width='7ch' />}
            </Link>
          </p>
        )}
        <StatusHeaderIndicators
          status={status}
          collapsed={collapsed}
          onCollapsedChange={onCollapsedChange}
        />
        {!collapsed &&
          showInstance &&
          status.instance_metadata &&
          (showLocalInstance ||
            !isLocalInstanceDomain(status.instance_metadata.domain)) && (
            <InstanceBadge instanceInfo={status.instance_metadata} compact />
          )}
      </div>

      {children}
    </header>
  );
};

const StatusHeaderIndicators: React.FC<
  Pick<StatusRedesignHeaderProps, 'status' | 'collapsed' | 'onCollapsedChange'>
> = ({ status, collapsed = false, onCollapsedChange }) => {
  const intl = useIntl();
  const settings = useAppSelector(
    (state) =>
      state.local_settings.get('status_icons') as ImmutableMap<string, boolean>,
  );
  const collapseEnabled = useAppSelector(
    (state) =>
      state.local_settings.getIn(['collapsed', 'enabled'], false) as boolean,
  );
  const language =
    settings.get('language') &&
    languages?.find(([code]) => code === status.language);
  const mediaIcons = new Set<IconName>();
  if (settings.get('media')) {
    for (const media of status.media_attachments) {
      if (media.type === 'image' || media.type === 'unknown')
        mediaIcons.add('picture-o');
      if (media.type === 'video' || media.type === 'gifv')
        mediaIcons.add('video-camera');
      if (media.type === 'audio') mediaIcons.add('music');
    }
    if (status.card) mediaIcons.add('link');
    if (status.poll) mediaIcons.add('tasks');
  }

  return (
    <div className={classes.indicators}>
      {status.rp_hidden && (
        <Badge
          variant='danger'
          label={
            <FormattedMessage id='status.rp_hidden' defaultMessage='Deleted' />
          }
        />
      )}
      {language && (
        <span title={`${language[2]} (${language[1]})`} aria-hidden='true'>
          {language[0].toUpperCase()}
        </span>
      )}
      {settings.get('reply') && status.in_reply_to_id && (
        <Icon
          id='comment'
          icon={ForumIcon}
          aria-label={intl.formatMessage(messages.reply)}
        />
      )}
      {settings.get('local_only') && status.local_only && (
        <Icon
          id='home'
          icon={HomeIcon}
          aria-label={intl.formatMessage(messages.localOnly)}
        />
      )}
      {Array.from(mediaIcons, (icon) => (
        <MediaIcon key={icon} icon={icon} className={classes.mediaIcon} />
      ))}
      {settings.get('visibility') &&
        (status.limited_scope === 'circle' ? (
          <FormattedMessage id='privacy.circle.short' defaultMessage='Circle' />
        ) : (
          <VisibilityIcon visibility={status.visibility} />
        ))}
      {collapseEnabled && onCollapsedChange && (
        <CollapseButton
          collapsed={collapsed}
          setCollapsed={onCollapsedChange}
        />
      )}
    </div>
  );
};
