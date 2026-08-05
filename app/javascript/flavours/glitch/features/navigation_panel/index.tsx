import type { MouseEventHandler } from 'react';
import { useEffect, useCallback, useRef } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';
import { useLocation } from 'react-router-dom';

import type { Map as ImmutableMap } from 'immutable';

import { animated, useSpring } from '@react-spring/web';
import { useDrag } from '@use-gesture/react';

import InfoIcon from '@/material-icons/400-24px/info.svg?react';
import AdministrationIcon from '@/material-icons/400-24px/manufacturing.svg?react';
import PersonAddActiveIcon from '@/material-icons/400-24px/person_add-fill.svg?react';
import PersonAddIcon from '@/material-icons/400-24px/person_add.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings.svg?react';
import { fetchFollowRequests } from 'flavours/glitch/actions/accounts';
import { openModal } from 'flavours/glitch/actions/modal';
import {
  openNavigation,
  closeNavigation,
} from 'flavours/glitch/actions/navigation';
import { Account } from 'flavours/glitch/components/account';
import { IconWithBadge } from 'flavours/glitch/components/icon_with_badge';
import { Search } from 'flavours/glitch/features/compose/components/search';
import { ColumnLink } from 'flavours/glitch/features/ui/components/column_link';
import { getNavigationSkipLinkId } from 'flavours/glitch/features/ui/components/skip_links';
import { useBreakpoint } from 'flavours/glitch/features/ui/hooks/useBreakpoint';
import { useIdentity } from 'flavours/glitch/identity_context';
import { me } from 'flavours/glitch/initial_state';
import { transientSingleColumn } from 'flavours/glitch/is_mobile';
import {
  SharlayanAntennaPanel,
  SharlayanNavigationExtensions,
  useSharlayanPrimaryNavigation,
} from 'flavours/glitch/sharlayan/registry/navigation';
import { useAppSelector, useAppDispatch } from 'flavours/glitch/store';

import { AnnualReportNavItem } from '../annual_report/nav_item';

import { DisabledAccountBanner } from './components/disabled_account_banner';
import { FollowedTagsPanel } from './components/followed_tags_panel';
import { ListPanel } from './components/list_panel';
import { MoreLink } from './components/more_link';
import { SignInBanner } from './components/sign_in_banner';
import { Trends } from './components/trends';

const messages = defineMessages({
  main: {
    id: 'navigation_bar.main',
    defaultMessage: 'Main',
    description:
      'Label for the main navigation; should not contain the word "navigation".',
  },
  preferences: {
    id: 'navigation_bar.preferences',
    defaultMessage: 'Preferences',
  },
  followsAndFollowers: {
    id: 'navigation_bar.follows_and_followers',
    defaultMessage: 'Follows and followers',
  },
  about: { id: 'navigation_bar.about', defaultMessage: 'About' },
  search: { id: 'navigation_bar.search', defaultMessage: 'Search' },
  searchTrends: {
    id: 'navigation_bar.search_trends',
    defaultMessage: 'Search / Trending',
  },
  advancedInterface: {
    id: 'navigation_bar.advanced_interface',
    defaultMessage: 'Open in advanced web interface',
  },
  openedInClassicInterface: {
    id: 'navigation_bar.opened_in_classic_interface',
    defaultMessage:
      'Posts, accounts, and other specific pages are opened by default in the classic web interface.',
  },
  followRequests: {
    id: 'navigation_bar.follow_requests',
    defaultMessage: 'Follow requests',
  },
  logout: { id: 'navigation_bar.logout', defaultMessage: 'Logout' },
  app_settings: {
    id: 'navigation_bar.app_settings',
    defaultMessage: 'App settings',
  },
});

const FollowRequestsLink: React.FC = () => {
  const intl = useIntl();
  const count = useAppSelector(
    (state) =>
      (
        state.user_lists.getIn(['follow_requests', 'items']) as
          | ImmutableMap<string, unknown>
          | undefined
      )?.size ?? 0,
  );
  const dispatch = useAppDispatch();

  useEffect(() => {
    dispatch(fetchFollowRequests());
  }, [dispatch]);

  if (count === 0) {
    return null;
  }

  return (
    <ColumnLink
      transparent
      to='/follow_requests'
      icon={
        <IconWithBadge
          id='user-plus'
          icon={PersonAddIcon}
          count={count}
          className='column-link__icon'
        />
      }
      activeIcon={
        <IconWithBadge
          id='user-plus'
          icon={PersonAddActiveIcon}
          count={count}
          className='column-link__icon'
        />
      }
      text={intl.formatMessage(messages.followRequests)}
    />
  );
};

const ProfileCard: React.FC = () => {
  if (!me) {
    return null;
  }

  return (
    <div className='navigation-bar'>
      <Account id={me} minimal size={36} />
    </div>
  );
};

const MENU_WIDTH = 284;

export const NavigationPanel: React.FC<{ multiColumn?: boolean }> = ({
  multiColumn = false,
}) => {
  const intl = useIntl();
  const { signedIn, disabledAccountId } = useIdentity();
  const location = useLocation();
  const showSearch = useBreakpoint('full') && !multiColumn;
  const dispatch = useAppDispatch();
  const { primaryItems, aboutGetsSkipLink } =
    useSharlayanPrimaryNavigation(multiColumn);

  let banner: React.ReactNode;

  if (transientSingleColumn) {
    banner = (
      <div className='switch-to-advanced'>
        {intl.formatMessage(messages.openedInClassicInterface)}{' '}
        <a
          href={`/deck${location.pathname}`}
          className='switch-to-advanced__toggle'
        >
          {intl.formatMessage(messages.advancedInterface)}
        </a>
      </div>
    );
  }

  const handleOpenSettings = useCallback<MouseEventHandler>(
    (e) => {
      e.preventDefault();
      e.stopPropagation();

      dispatch(
        openModal({
          modalType: 'SETTINGS',
          modalProps: {},
        }),
      );
    },
    [dispatch],
  );

  return (
    <nav
      className='navigation-panel'
      aria-label={intl.formatMessage(messages.main)}
    >
      {showSearch && <Search singleColumn />}

      {!multiColumn && <ProfileCard />}

      {banner && <div className='navigation-panel__banner'>{banner}</div>}

      <ul className='navigation-panel__menu'>
        {primaryItems}

        {signedIn && (
          <>
            <li>
              <FollowRequestsLink />
            </li>

            <li>
              <AnnualReportNavItem />
            </li>

            <li role='separator' />

            <SharlayanNavigationExtensions />

            <ListPanel />

            <SharlayanAntennaPanel />

            <FollowedTagsPanel />

            <li role='separator' />

            <li>
              <ColumnLink
                transparent
                href='/settings/preferences'
                icon='cog'
                iconComponent={SettingsIcon}
                text={intl.formatMessage(messages.preferences)}
              />
            </li>
            <li>
              <ColumnLink
                transparent
                onClick={handleOpenSettings}
                icon='cogs'
                iconComponent={AdministrationIcon}
                text={intl.formatMessage(messages.app_settings)}
              />
            </li>

            <li>
              <MoreLink />
            </li>
          </>
        )}

        <li className='navigation-panel__legal'>
          <ColumnLink
            transparent
            to='/about'
            icon='ellipsis-h'
            iconComponent={InfoIcon}
            text={intl.formatMessage(messages.about)}
            id={aboutGetsSkipLink ? getNavigationSkipLinkId() : undefined}
          />
        </li>

        {!signedIn && (
          <li className='navigation-panel__sign-in-banner'>
            <hr />

            {disabledAccountId ? <DisabledAccountBanner /> : <SignInBanner />}
          </li>
        )}
      </ul>

      <div className='flex-spacer' />

      <Trends />
    </nav>
  );
};

export const CollapsibleNavigationPanel: React.FC = () => {
  const open = useAppSelector((state) => state.navigation.open);
  const dispatch = useAppDispatch();
  const openable = useBreakpoint('openable');
  const location = useLocation();
  const overlayRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    dispatch(closeNavigation());
  }, [dispatch, location]);

  useEffect(() => {
    const handleDocumentClick = (e: MouseEvent) => {
      if (overlayRef.current && e.target === overlayRef.current) {
        dispatch(closeNavigation());
      }
    };

    const handleDocumentKeyUp = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        dispatch(closeNavigation());
      }
    };

    document.addEventListener('click', handleDocumentClick);
    document.addEventListener('keyup', handleDocumentKeyUp);

    return () => {
      document.removeEventListener('click', handleDocumentClick);
      document.removeEventListener('keyup', handleDocumentKeyUp);
    };
  }, [dispatch]);

  const isLtrDir = getComputedStyle(document.body).direction !== 'rtl';

  const OPEN_MENU_OFFSET = isLtrDir ? MENU_WIDTH : -MENU_WIDTH;

  const [{ x }, spring] = useSpring(
    () => ({
      x: open ? 0 : OPEN_MENU_OFFSET,
      onRest: {
        x({ value }: { value: number }) {
          if (value === 0) {
            dispatch(openNavigation());
          } else if (value === OPEN_MENU_OFFSET) {
            dispatch(closeNavigation());
          }
        },
      },
    }),
    [open],
  );

  const bind = useDrag(
    ({
      last,
      offset: [xOffset],
      velocity: [xVelocity],
      direction: [xDirection],
      cancel,
    }) => {
      const logicalXDirection = isLtrDir ? xDirection : -xDirection;
      const logicalXOffset = isLtrDir ? xOffset : -xOffset;
      const hasReachedDragThreshold = logicalXOffset < -70;

      if (hasReachedDragThreshold) {
        cancel();
      }

      if (last) {
        const isAboveOpenThreshold = logicalXOffset > MENU_WIDTH / 2;
        const isQuickFlick = xVelocity > 0.5 && logicalXDirection > 0;

        if (isAboveOpenThreshold || isQuickFlick) {
          void spring.start({ x: OPEN_MENU_OFFSET });
        } else {
          void spring.start({ x: 0 });
        }
      } else {
        void spring.start({ x: xOffset, immediate: true });
      }
    },
    {
      from: () => [x.get(), 0],
      axis: 'x',
      filterTaps: true,
      bounds: isLtrDir ? { left: 0 } : { right: 0 },
      rubberband: true,
      enabled: openable,
    },
  );

  const previouslyFocusedElementRef = useRef<HTMLElement>(null);

  useEffect(() => {
    if (open) {
      const firstLink = document.querySelector<HTMLAnchorElement>(
        '.navigation-panel__menu .column-link',
      );
      previouslyFocusedElementRef.current =
        document.activeElement as HTMLElement;
      firstLink?.focus();
    } else {
      previouslyFocusedElementRef.current?.focus();
    }
  }, [open]);

  const showOverlay = openable && open;

  return (
    <div
      className={classNames(
        'columns-area__panels__pane columns-area__panels__pane--start columns-area__panels__pane--navigational',
        { 'columns-area__panels__pane--overlay': showOverlay },
      )}
      ref={overlayRef}
    >
      <animated.div
        className='columns-area__panels__pane__inner'
        {...bind()}
        style={openable ? { x } : undefined}
      >
        <NavigationPanel />
      </animated.div>
    </div>
  );
};
