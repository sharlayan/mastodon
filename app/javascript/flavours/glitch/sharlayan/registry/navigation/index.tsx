import { useEffect, useMemo } from 'react';
import type { ReactNode } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import AddIcon from '@/material-icons/400-24px/add.svg?react';
import AlternateEmailIcon from '@/material-icons/400-24px/alternate_email.svg?react';
import BookmarksActiveIcon from '@/material-icons/400-24px/bookmarks-fill.svg?react';
import BookmarksIcon from '@/material-icons/400-24px/bookmarks.svg?react';
import CampaignActiveIcon from '@/material-icons/400-24px/campaign-fill.svg?react';
import CampaignIcon from '@/material-icons/400-24px/campaign.svg?react';
import CollectionsActiveIcon from '@/material-icons/400-24px/category-fill.svg?react';
import CollectionsIcon from '@/material-icons/400-24px/category.svg?react';
import PeopleIcon from '@/material-icons/400-24px/group.svg?react';
import HomeActiveIcon from '@/material-icons/400-24px/home-fill.svg?react';
import HomeIcon from '@/material-icons/400-24px/home.svg?react';
import NotificationsActiveIcon from '@/material-icons/400-24px/notifications-fill.svg?react';
import NotificationsIcon from '@/material-icons/400-24px/notifications.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';
import StarActiveIcon from '@/material-icons/400-24px/star-fill.svg?react';
import StarIcon from '@/material-icons/400-24px/star.svg?react';
import TrendingUpIcon from '@/material-icons/400-24px/trending_up.svg?react';
import { fetchBoardAnnouncementsUnreadCount } from 'flavours/glitch/actions/board_announcements';
import { IconWithBadge } from 'flavours/glitch/components/icon_with_badge';
import { AntennaPanel } from 'flavours/glitch/features/navigation_panel/components/antenna_panel';
import { ExtensionsPanel } from 'flavours/glitch/features/navigation_panel/components/extensions_panel';
import { ColumnLink } from 'flavours/glitch/features/ui/components/column_link';
import { getNavigationSkipLinkId } from 'flavours/glitch/features/ui/components/skip_links';
import { useConfirmDraftBeforePublish } from 'flavours/glitch/features/ui/hooks/use_confirm_draft_before_publish';
import { useBreakpoint } from 'flavours/glitch/features/ui/hooks/useBreakpoint';
import { useAccount } from 'flavours/glitch/hooks/useAccount';
import { useIdentity } from 'flavours/glitch/identity_context';
import {
  antennaEnabled,
  boardAnnouncementsEnabled,
  localLiveFeedAccess,
  me,
  remoteLiveFeedAccess,
  trendsEnabled,
} from 'flavours/glitch/initial_state';
import { canViewFeed } from 'flavours/glitch/permissions';
import { selectUnreadNotificationGroupsCount } from 'flavours/glitch/selectors/notifications';
import {
  collectionsEnabled,
  roleplayMode,
} from 'flavours/glitch/sharlayan/roleplay';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

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
  direct: { id: 'navigation_bar.direct', defaultMessage: 'Private mentions' },
  favourites: { id: 'navigation_bar.favourites', defaultMessage: 'Favorites' },
  bookmarks: { id: 'navigation_bar.bookmarks', defaultMessage: 'Bookmarks' },
  collections: {
    id: 'navigation_bar.collections',
    defaultMessage: 'Collections',
  },
  boardAnnouncements: {
    id: 'navigation_bar.board_announcements',
    defaultMessage: 'Announcements',
  },
  compose: { id: 'tabs_bar.publish', defaultMessage: 'New Post' },
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

const BoardAnnouncementsLink = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const count = useAppSelector((state) => state.boardAnnouncements.unreadCount);

  useEffect(() => {
    void dispatch(fetchBoardAnnouncementsUnreadCount());
  }, [dispatch]);

  return (
    <ColumnLink
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

export const useSharlayanPrimaryNavigation = (
  multiColumn: boolean,
): {
  primaryItems: ReactNode;
  aboutGetsSkipLink: boolean;
} => {
  const intl = useIntl();
  const { signedIn, permissions } = useIdentity();
  const account = useAccount(me);
  const navOrder = useAppSelector(
    (state) =>
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access
      state.local_settings.getIn(['navigation_panel', 'order']) as
        | ImmutableList<string>
        | undefined,
  );
  const navHidden = useAppSelector(
    (state) =>
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access
      state.local_settings.getIn(['navigation_panel', 'hidden']) as
        | ImmutableMap<string, boolean>
        | undefined,
  );
  const isMobileLayout = useBreakpoint('openable');
  const confirmDraftBeforePublish = useConfirmDraftBeforePublish();
  const orderedKeys = useMemo(
    () => computeNavigationOrder(navOrder?.toArray()),
    [navOrder],
  );
  const feedsAllowed =
    canViewFeed(signedIn, permissions, localLiveFeedAccess) ||
    canViewFeed(signedIn, permissions, remoteLiveFeedAccess);
  const renderers: Partial<Record<string, (id?: string) => ReactNode>> = {};

  if (signedIn) {
    renderers.home = (id) => (
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
    renderers.explore = (id) => (
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
      renderers.federated = (id) => (
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
    renderers.local = (id) => (
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
    renderers.notifications = () => <NotificationsLink />;
    renderers.favourites = (id) => (
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
    renderers.bookmarks = (id) => (
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
    if (collectionsEnabled) {
      renderers.collections = (id) => (
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
    renderers.direct = (id) => (
      <ColumnLink
        transparent
        to='/conversations'
        icon='at'
        iconComponent={AlternateEmailIcon}
        text={intl.formatMessage(messages.direct)}
        id={id}
      />
    );
    if (boardAnnouncementsEnabled) {
      renderers.board_announcements = () => <BoardAnnouncementsLink />;
    }
  }

  const composeShown = signedIn && !multiColumn;
  const visibleKeys = orderedKeys.filter(
    (key) =>
      renderers[key] &&
      (isMobileLayout ||
        isNavigationItemAlwaysVisible(key) ||
        navHidden?.get(key) !== true),
  );
  const skipLinkKey = composeShown ? undefined : visibleKeys[0];

  return {
    primaryItems: (
      <>
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
              onClick={confirmDraftBeforePublish}
            />
          </li>
        )}
        {visibleKeys.map((key) => (
          <li key={key}>
            {renderers[key]?.(
              key === skipLinkKey ? getNavigationSkipLinkId() : undefined,
            )}
          </li>
        ))}
      </>
    ),
    aboutGetsSkipLink: !composeShown && visibleKeys.length === 0,
  };
};

export const SharlayanNavigationExtensions = () => (
  <>
    <ExtensionsPanel />
    <li role='separator' />
  </>
);

export const SharlayanAntennaPanel = () =>
  antennaEnabled ? <AntennaPanel /> : null;
