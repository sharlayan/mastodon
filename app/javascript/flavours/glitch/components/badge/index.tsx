import type { FC, ReactNode } from 'react';

import { FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';

import { isRedesignEnabled } from '@/flavours/glitch/utils/environment';
import type { OnAttributeHandler } from '@/flavours/glitch/utils/html';
import AdminIcon from '@/images/icons/icon_admin.svg?react';
import ClockIcon from '@/images/icons/icon_clock.svg?react';
import FollowerIcon from '@/images/icons/icon_follower.svg?react';
import IconVerified from '@/images/icons/icon_verified.svg?react';
import BlockIcon from '@/material-icons/400-24px/block.svg?react';
import GroupsIcon from '@/material-icons/400-24px/group.svg?react';
import SmartToyIcon from '@/material-icons/400-24px/smart_toy.svg?react';
import VolumeOffIcon from '@/material-icons/400-24px/volume_off.svg?react';

import { EmojiHTML } from '../emoji/html';
import { Icon } from '../icon';

import redesignClasses from './redesign.module.scss';
import classes from './styles.module.scss';

const readableTextColor = (hex: string) => {
  const value = hex.replace('#', '');
  if (value.length !== 3 && value.length !== 6) {
    return undefined;
  }
  const full =
    value.length === 3
      ? value
          .split('')
          .map((c) => c + c)
          .join('')
      : value;
  const r = parseInt(full.slice(0, 2), 16);
  const g = parseInt(full.slice(2, 4), 16);
  const b = parseInt(full.slice(4, 6), 16);
  if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
    return undefined;
  }
  const luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  return luminance > 0.6 ? '#000000' : '#ffffff';
};

interface BadgeProps extends React.ComponentPropsWithoutRef<'div'> {
  label: ReactNode;
  icon?: ReactNode;
  domain?: ReactNode;
  roleId?: string;
  color?: string;
  variant?:
    | 'default'
    | 'subtle'
    | 'accent'
    | 'inverted'
    | 'success'
    | 'warning'
    | 'danger';
}

type PresetBadgeProps = Omit<
  BadgeProps,
  'label' | 'icon' | 'domain' | 'roleId'
>;

export const Badge: FC<BadgeProps> = ({
  icon,
  variant = 'default',
  label,
  className,
  domain,
  roleId,
  color,
  style,
  ...otherProps
}) => (
  <div
    {...otherProps}
    className={classNames(
      classes.badge,
      isRedesignEnabled() && redesignClasses.badge,
      !icon && [classes.badgeWithoutIcon, redesignClasses.badgeWithoutIcon],
      classes[variant],
      className,
    )}
    style={
      color
        ? { backgroundColor: color, color: readableTextColor(color), ...style }
        : style
    }
    data-account-role-id={roleId}
  >
    {icon}
    <span className={classes.content}>
      {label}
      {domain && <span className={classes.domain}> {domain}</span>}
    </span>
  </div>
);

export const AdminBadge: FC<Partial<BadgeProps>> = ({ label, ...props }) => (
  <Badge
    icon={<AdminIcon />}
    label={
      label ?? (
        <FormattedMessage id='account.badges.admin' defaultMessage='Admin' />
      )
    }
    {...props}
  />
);

export const GroupBadge: FC<Partial<BadgeProps>> = ({ label, ...props }) => (
  <Badge
    icon={<GroupsIcon />}
    label={
      label ?? (
        <FormattedMessage id='account.badges.group' defaultMessage='Group' />
      )
    }
    {...props}
  />
);

export const AutomatedBadge: FC<PresetBadgeProps> = (props) => (
  <Badge
    icon={<SmartToyIcon />}
    label={
      <FormattedMessage id='account.badges.bot' defaultMessage='Automated' />
    }
    {...props}
  />
);

export const FollowsYouBadge: FC<PresetBadgeProps> = (props) => (
  <Badge
    icon={<FollowerIcon />}
    label={
      <FormattedMessage id='account.follows_you' defaultMessage='Follows you' />
    }
    {...props}
  />
);

export const PendingBadge: FC<PresetBadgeProps> = (props) => (
  <Badge
    variant='warning'
    icon={<ClockIcon />}
    label={<FormattedMessage id='account.pending' defaultMessage='Pending' />}
    {...props}
  />
);

export const MutedBadge: FC<
  Partial<BadgeProps> & { expiresAt?: string | null }
> = ({ expiresAt, label, ...props }) => {
  // Format the date, only showing the year if it's different from the current year.
  const intl = useIntl();
  let formattedDate: string | null = null;
  if (expiresAt) {
    const expiresDate = new Date(expiresAt);
    const isCurrentYear =
      expiresDate.getFullYear() === new Date().getFullYear();
    formattedDate = intl.formatDate(expiresDate, {
      month: 'short',
      day: 'numeric',
      ...(isCurrentYear ? {} : { year: 'numeric' }),
    });
  }
  return (
    <Badge
      icon={<VolumeOffIcon />}
      variant='inverted'
      label={
        label ??
        (formattedDate ? (
          <FormattedMessage
            id='account.badges.muted_until'
            defaultMessage='Muted until {until}'
            values={{
              until: formattedDate,
            }}
          />
        ) : (
          <FormattedMessage id='account.badges.muted' defaultMessage='Muted' />
        ))
      }
      {...props}
    />
  );
};

export const BlockedBadge: FC<Partial<BadgeProps>> = ({ label, ...props }) => (
  <Badge
    icon={<BlockIcon />}
    variant='danger'
    label={
      label ?? (
        <FormattedMessage
          id='account.badges.blocked'
          defaultMessage='Blocked'
        />
      )
    }
    {...props}
  />
);

const onAttribute: OnAttributeHandler = (name, value, tagName) => {
  if (name === 'rel' && tagName === 'a') {
    if (value === 'me') {
      return null;
    }
    return [
      name,
      value
        .split(' ')
        .filter((x) => x !== 'me')
        .join(' '),
    ];
  }
  return undefined;
};

export const VerifiedBadge: React.FC<{ link: string; className?: string }> = ({
  link,
  className,
}) => (
  <Badge
    variant='success'
    icon={<Icon id='verified' icon={IconVerified} noFill />}
    label={<EmojiHTML as='span' htmlString={link} onAttribute={onAttribute} />}
    className={className}
  />
);
