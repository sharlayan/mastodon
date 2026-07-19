import type { MouseEventHandler } from 'react';
import { useCallback } from 'react';

import classNames from 'classnames';
import { useRouteMatch, NavLink, useLocation } from 'react-router-dom';

import { Icon } from 'flavours/glitch/components/icon';
import type { IconProp } from 'flavours/glitch/components/icon';
import type { MastodonLocationDescriptor } from 'flavours/glitch/components/router';

export const ColumnLink: React.FC<{
  icon: React.ReactNode;
  iconComponent?: IconProp;
  activeIcon?: React.ReactNode;
  activeIconComponent?: IconProp;
  isActive?: (match: unknown, location: { pathname: string }) => boolean;
  text: string;
  to?: MastodonLocationDescriptor;
  onClick?: MouseEventHandler;
  href?: string;
  method?: string;
  badge?: React.ReactNode;
  transparent?: boolean;
  className?: string;
  id?: string;
}> = ({
  icon,
  activeIcon,
  iconComponent,
  activeIconComponent,
  text,
  to,
  onClick,
  href,
  method,
  badge,
  transparent,
  ...other
}) => {
  const location = useLocation();
  const toPath = (typeof to === 'string' ? to : to?.pathname) ?? '';
  const routeMatch = useRouteMatch(toPath);
  const match =
    toPath === '/public' || toPath === '/public/local'
      ? location.pathname === toPath
      : routeMatch;
  const className = classNames('column-link', {
    'column-link--transparent': transparent,
  });
  const badgeElement =
    typeof badge !== 'undefined' ? (
      <span className='column-link__badge'>{badge}</span>
    ) : null;
  const iconElement = iconComponent ? (
    <Icon
      id={typeof icon === 'string' ? icon : ''}
      icon={iconComponent}
      className='column-link__icon'
    />
  ) : (
    icon
  );
  const activeIconElement =
    activeIcon ??
    (activeIconComponent ? (
      <Icon
        id={typeof icon === 'string' ? icon : ''}
        icon={activeIconComponent}
        className='column-link__icon'
      />
    ) : (
      iconElement
    ));
  const active = !!match;

  const navLinkIsActive = useCallback(() => {
    return location.pathname === toPath;
  }, [location.pathname, toPath]);

  if (href) {
    return (
      <a
        href={href}
        onClick={onClick}
        className={className}
        data-method={method}
        {...other}
      >
        {active ? activeIconElement : iconElement}
        <span>{text}</span>
        {badgeElement}
      </a>
    );
  } else if (to) {
    const shouldUseCustomIsActive =
      toPath === '/public' || toPath === '/public/local';
    return (
      <NavLink
        to={to}
        onClick={onClick}
        className={className}
        isActive={shouldUseCustomIsActive ? navLinkIsActive : undefined}
        {...other}
      >
        {active ? activeIconElement : iconElement}
        <span>{text}</span>
        {badgeElement}
      </NavLink>
    );
  } else {
    return (
      // eslint-disable-next-line jsx-a11y/anchor-is-valid -- intentional to have the same look and feel as other menu items
      <a
        href='#'
        onClick={onClick}
        className={className}
        {...other}
        tabIndex={0}
      >
        {iconElement}
        <span>{text}</span>
        {badgeElement}
      </a>
    );
  }
};
