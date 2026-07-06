import type { MouseEventHandler } from 'react';
import { useEffect, useCallback, useRef, useMemo } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';
import { useLocation } from 'react-router-dom';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import { animated, useSpring } from '@react-spring/web';
import { useDrag } from '@use-gesture/react';

import { useAccount } from '@/flavours/glitch/hooks/useAccount';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import AlternateEmailIcon from '@/material-icons/400-24px/alternate_email.svg?react';
import BookmarksActiveIcon from '@/material-icons/400-24px/bookmarks-fill.svg?react';
import BookmarksIcon from '@/material-icons/400-24px/bookmarks.svg?react';
import CalendarTodayIcon from '@/material-icons/400-24px/calendar_today.svg?react';
import CampaignActiveIcon from '@/material-icons/400-24px/campaign-fill.svg?react';
import CampaignIcon from '@/material-icons/400-24px/campaign.svg?react';
import CollectionsActiveIcon from '@/material-icons/400-24px/category-fill.svg?react';
import CollectionsIcon from '@/material-icons/400-24px/category.svg?react';
import PeopleIcon from '@/material-icons/400-24px/group.svg?react';
import HomeActiveIcon from '@/material-icons/400-24px/home-fill.svg?react';
import HomeIcon from '@/material-icons/400-24px/home.svg?react';
import InfoIcon from '@/material-icons/400-24px/info.svg?react';
import AdministrationIcon from '@/material-icons/400-24px/manufacturing.svg?react';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';
import NotificationsActiveIcon from '@/material-icons/400-24px/notifications-fill.svg?react';
import NotificationsIcon from '@/material-icons/400-24px/notifications.svg?react';
import PersonAddActiveIcon from '@/material-icons/400-24px/person_add-fill.svg?react';
import PersonAddIcon from '@/material-icons/400-24px/person_add.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings.svg?react';
import StarActiveIcon from '@/material-icons/400-24px/star-fill.svg?react';
import StarIcon from '@/material-icons/400-24px/star.svg?react';
import TrendingUpIcon from '@/material-icons/400-24px/trending_up.svg?react';
import { fetchFollowRequests } from 'flavours/glitch/actions/accounts';
import { fetchBoardAnnouncementsUnreadCount } from 'flavours/glitch/actions/board_announcements';
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
import {
  antennaEnabled,
  boardAnnouncementsEnabled,
  circlesEnabled,
  clipsEnabled,
  collectionsEnabled,
  localLiveFeedAccess,
  remoteLiveFeedAccess,
  trendsEnabled,
  roleplayMode,
  me,
} from 'flavours/glitch/initial_state';
import { transientSingleColumn } from 'flavours/glitch/is_mobile';
import { canViewFeed, isAdministrator } from 'flavours/glitch/permissions';
import { selectUnreadNotificationGroupsCount } from 'flavours/glitch/selectors/notifications';
import { useAppSelector, useAppDispatch } from 'flavours/glitch/store';

import { AnnualReportNavItem } from '../annual_report/nav_item';

import { AntennaPanel } from './components/antenna_panel';
import { DisabledAccountBanner } from './components/disabled_account_banner';
import { ExtensionsPanel } from './components/extensions_panel';
import { FollowedTagsPanel } from './components/followed_tags_panel';
import { ListPanel } from './components/list_panel';
import { MoreLink } from './components/more_link';
import { SignInBanner } from './components/sign_in_banner';
import { Trends } from './components/trends';
import { computeNavigationOrder, isNavigationItemAlwaysVisible } from './items';

const messages = defineMessages({
  home: { id: 'tabs_bar.home', defaultMessage: 'Home' },
  notifications: {
    id: 'tabs_bar.notifications',
    defaultMessage: 'Notifications',
  },
  explore: { id: 'explore.title', defaultMessage: 'Trending' },
  local: { id: 'navigation_bar.community_timeline', defaultMessage: 'Local' },
  localRoleplay: {
    id: 'navigation_bar.roleplay_public_timeline',
    defaultMessage: 'Public timeline',
  },
  federated: {
    id: 'navigation_bar.public_timeline',
    defaultMessage: 'Federated',
  },
  main: {
    id: 'navigation_bar.main',
    defaultMessage: 'Main',
    description:
      'Label for the main navigation; should not contain the word "navigation".',
  },
  direct: { id: 'navigation_bar.direct', defaultMessage: 'Private mentions' },
  adminTimeline: {
    id: 'navigation_bar.admin_timeline',
    defaultMessage: 'Management timeline',
  },
  circles: { id: 'navigation_bar.circles', defaultMessage: 'Circles' },
  favourites: { id: 'navigation_bar.favourites', defaultMessage: 'Favorites' },
  bookmarks: { id: 'navigation_bar.bookmarks', defaultMessage: 'Bookmarks' },
  clips: { id: 'navigation_bar.clips', defaultMessage: 'Clips' },
  scheduled: {
    id: 'navigation_bar.scheduled',
    defaultMessage: 'Scheduled posts',
  },
  collections: {
    id: 'navigation_bar.collections',
    defaultMessage: 'Collections',
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
  boardAnnouncements: {
    id: 'navigation_bar.board_announcements',
    defaultMessage: 'Announcements',
  },
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
  compose: { id: 'tabs_bar.publish', defaultMessage: 'New Post' },
  app_settings: {
    id: 'navigation_bar.app_settings',
    defaultMessage: 'App settings',
  },
});

const NotificationsLink = () => {
  const count = useAppSelector(selectUnreadNotificationGroupsCount);
  const showCount = useAppSelector(
    (state) =>
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access
      state.local_settings.getIn(['notifications', 'tab_badge']) as boolean,
  );
  const intl = useIntl();

  return (
    <ColumnLink
      key='notifications'
      transparent
      to='/notifications'
      icon={
        <IconWithBadge
          id='bell'
          icon={NotificationsIcon}
          count={showCount ? count : 0}
          className='column-link__icon'
        />
      }
      activeIcon={
        <IconWithBadge
          id='bell'
          icon={NotificationsActiveIcon}
          count={showCount ? count : 0}
          className='column-link__icon'
        />
      }
      text={intl.formatMessage(messages.notifications)}
    />
  );
};

const BoardAnnouncementsLink: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const count = useAppSelector((state) => state.boardAnnouncements.unreadCount);

  useEffect(() => {
    void dispatch(fetchBoardAnnouncementsUnreadCount());
  }, [dispatch]);

  return (
    <ColumnLink
      key='board_announcements'
      transparent
      to='/board_announcements'
      icon={
        <IconWithBadge
          id='campaign'
          icon={CampaignIcon}
          count={count}
          className='column-link__icon'
        />
      }
      activeIcon={
        <IconWithBadge
          id='campaign'
          icon={CampaignActiveIcon}
          count={count}
          className='column-link__icon'
        />
      }
      text={intl.formatMessage(messages.boardAnnouncements)}
    />
  );
};

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
  const { signedIn, permissions, disabledAccountId } = useIdentity();
  const location = useLocation();
  const showSearch = useBreakpoint('full') && !multiColumn;
  const account = useAccount(me);
  const dispatch = useAppDispatch();

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

  const navOrder = useAppSelector(
    (state) =>
      // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-unsafe-call
      state.local_settings.getIn(['navigation_panel', 'order']) as
        | ImmutableList<string>
        | undefined,
  );
  const navHidden = useAppSelector(
    (state) =>
      // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-unsafe-call
      state.local_settings.getIn(['navigation_panel', 'hidden']) as
        | ImmutableMap<string, boolean>
        | undefined,
  );
  const isMobileLayout = useBreakpoint('openable');

  const orderedKeys = useMemo(
    () => computeNavigationOrder(navOrder ? navOrder.toArray() : undefined),
    [navOrder],
  );

  const feedsAllowed =
    canViewFeed(signedIn, permissions, localLiveFeedAccess) ||
    canViewFeed(signedIn, permissions, remoteLiveFeedAccess);

  const itemRenderers: Partial<
    Record<string, (id?: string) => React.ReactNode>
  > = {};

  if (signedIn) {
    itemRenderers.home = (id) => (
      <ColumnLink
        transparent
        to='/home'
        icon='home'
        iconComponent={HomeIcon}
        activeIconComponent={HomeActiveIcon}
        text={intl.formatMessage(messages.home)}
        id={id}
      />
    );
  }

  if (trendsEnabled) {
    itemRenderers.explore = (id) => (
      <ColumnLink
        transparent
        to='/explore'
        icon='explore'
        iconComponent={TrendingUpIcon}
        text={intl.formatMessage(messages.explore)}
        id={id}
      />
    );
  }

  if (feedsAllowed) {
    if (!roleplayMode) {
      itemRenderers.federated = (id) => (
        <ColumnLink
          transparent
          to='/public'
          icon='globe'
          iconComponent={PublicIcon}
          text={intl.formatMessage(messages.federated)}
          id={id}
        />
      );
    }
    itemRenderers.local = (id) => (
      <ColumnLink
        transparent
        to='/public/local'
        icon='users'
        iconComponent={PeopleIcon}
        text={intl.formatMessage(
          roleplayMode ? messages.localRoleplay : messages.local,
        )}
        id={id}
      />
    );
  }

  if (signedIn) {
    itemRenderers.notifications = () => <NotificationsLink />;
    itemRenderers.favourites = (id) => (
      <ColumnLink
        transparent
        to='/favourites'
        icon='star'
        iconComponent={StarIcon}
        activeIconComponent={StarActiveIcon}
        text={intl.formatMessage(messages.favourites)}
        id={id}
      />
    );
    itemRenderers.bookmarks = (id) => (
      <ColumnLink
        transparent
        to='/bookmarks'
        icon='bookmarks'
        iconComponent={BookmarksIcon}
        activeIconComponent={BookmarksActiveIcon}
        text={intl.formatMessage(messages.bookmarks)}
        id={id}
      />
    );
    if (clipsEnabled) {
      itemRenderers.clips = (id) => (
        <ColumnLink
          transparent
          to='/clips'
          icon='note-stack-add'
          iconComponent={NoteStackAddIcon}
          text={intl.formatMessage(messages.clips)}
          id={id}
        />
      );
    }
    itemRenderers.scheduled = (id) => (
      <ColumnLink
        transparent
        to='/scheduled'
        icon='calendar'
        iconComponent={CalendarTodayIcon}
        text={intl.formatMessage(messages.scheduled)}
        id={id}
      />
    );
    if (collectionsEnabled) {
      itemRenderers.collections = (id) => (
        <ColumnLink
          transparent
          to={`/@${account?.acct}/collections`}
          icon='collections'
          iconComponent={CollectionsIcon}
          activeIconComponent={CollectionsActiveIcon}
          text={intl.formatMessage(messages.collections)}
          id={id}
        />
      );
    }
    itemRenderers.direct = (id) => (
      <ColumnLink
        transparent
        to='/conversations'
        icon='at'
        iconComponent={AlternateEmailIcon}
        text={intl.formatMessage(messages.direct)}
        id={id}
      />
    );
    if (circlesEnabled) {
      itemRenderers.circles = (id) => (
        <ColumnLink
          transparent
          to='/circles'
          icon='group'
          iconComponent={PeopleIcon}
          text={intl.formatMessage(messages.circles)}
          id={id}
        />
      );
    }
    if (boardAnnouncementsEnabled) {
      itemRenderers.board_announcements = () => <BoardAnnouncementsLink />;
    }
    if (roleplayMode && isAdministrator(permissions)) {
      itemRenderers.admin_timeline = (id) => (
        <ColumnLink
          transparent
          to='/timelines/admin'
          icon='manufacturing'
          iconComponent={AdministrationIcon}
          text={intl.formatMessage(messages.adminTimeline)}
          id={id}
        />
      );
    }
  }

  const composeShown = signedIn && !multiColumn;

  const visibleKeys = orderedKeys.filter(
    (key) =>
      itemRenderers[key] &&
      (isMobileLayout ||
        isNavigationItemAlwaysVisible(key) ||
        navHidden?.get(key) !== true),
  );

  const skipLinkKey = composeShown ? undefined : visibleKeys[0];
  const aboutGetsSkipLink = !composeShown && visibleKeys.length === 0;

  const navigationItems = visibleKeys.map((key) => (
    <li key={key}>
      {itemRenderers[key]?.(
        key === skipLinkKey ? getNavigationSkipLinkId() : undefined,
      )}
    </li>
  ));

  return (
    <nav
      className='navigation-panel'
      aria-label={intl.formatMessage(messages.main)}
    >
      {showSearch && <Search singleColumn />}

      {!multiColumn && <ProfileCard />}

      {banner && <div className='navigation-panel__banner'>{banner}</div>}

      <ul className='navigation-panel__menu'>
        {composeShown && (
          <li>
            <ColumnLink
              to={{ pathname: '/publish', state: { focusTarget: false } }}
              icon='plus'
              iconComponent={AddIcon}
              activeIconComponent={AddIcon}
              text={intl.formatMessage(messages.compose)}
              className='button navigation-panel__compose-button'
              id={getNavigationSkipLinkId()}
            />
          </li>
        )}

        {navigationItems}

        {signedIn && (
          <>
            <li>
              <FollowRequestsLink />
            </li>

            <li>
              <AnnualReportNavItem />
            </li>

            <li role='separator' />

            <ExtensionsPanel />

            <li role='separator' />

            <ListPanel />

            {antennaEnabled && <AntennaPanel />}

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
          } else if (isLtrDir ? value > 0 : value < 0) {
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
