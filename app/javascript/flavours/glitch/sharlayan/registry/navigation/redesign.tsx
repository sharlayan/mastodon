import { useEffect } from 'react';

import { FormattedMessage, useIntl } from 'react-intl';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import {
  BankIcon,
  BellIcon,
  BookmarkSimpleIcon,
  CalendarIcon,
  ChatCircleDotsIcon,
  CirclesFourIcon,
  EyeSlashIcon,
  FileTextIcon,
  FloppyDiskIcon,
  GlobeIcon,
  HeartIcon,
  HouseIcon,
  MegaphoneIcon,
  RssSimpleIcon,
  SmileyIcon,
  StackIcon,
  TrendUpIcon,
  UsersIcon,
} from '@phosphor-icons/react';
import type { Icon } from '@phosphor-icons/react';

import { fetchAntennas } from '@/flavours/glitch/actions/antennas';
import { fetchBoardAnnouncementsUnreadCount } from '@/flavours/glitch/actions/board_announcements';
import { openModal } from '@/flavours/glitch/actions/modal';
import { LegacyDropdownMenuItems } from '@/flavours/glitch/components/menu';
import { ListSection } from '@/flavours/glitch/features/navigation_panel/redesign/list_section';
import { NavigationLink } from '@/flavours/glitch/features/navigation_panel/redesign/navigation_link';
import { useBreakpoint } from '@/flavours/glitch/features/ui/hooks/useBreakpoint';
import { useAccount } from '@/flavours/glitch/hooks/useAccount';
import { useIdentity } from '@/flavours/glitch/identity_context';
import {
  antennaEnabled,
  boardAnnouncementsEnabled,
  circlesEnabled,
  clipsEnabled,
  collectionsEnabled,
  driveEnabled,
  federatedTimelineEnabled,
  localLiveFeedAccess,
  localTimelineEnabled,
  pagesEnabled,
  remoteLiveFeedAccess,
  trendsEnabled,
} from '@/flavours/glitch/initial_state';
import type { MenuItem } from '@/flavours/glitch/models/dropdown_menu';
import { canViewFeed } from '@/flavours/glitch/permissions';
import {
  adminTimelineOwnerViewer,
  softHideDeletion,
} from '@/flavours/glitch/sharlayan/roleplay';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

import type { NavigationPanelItem } from './items';
import { navigationPanelItemMessages } from './items';
import { extendSharlayanMoreMenuItems } from './more_menu';
import { getRedesignNavigationKeys } from './redesign_items';

export const SharlayanRedesignPrimaryNavigation: React.FC<{
  showHidden?: boolean;
  notificationsCount: number;
}> = ({ showHidden = false, notificationsCount }) => {
  const intl = useIntl();
  const { signedIn, permissions, accountId } = useIdentity();
  const account = useAccount(accountId);
  const dispatch = useAppDispatch();
  const mobile = useBreakpoint('openable');
  const order = useAppSelector(
    (state) =>
      state.local_settings.getIn(['navigation_panel', 'order']) as
        | ImmutableList<string>
        | undefined,
  );
  const hidden = useAppSelector(
    (state) =>
      state.local_settings.getIn(['navigation_panel', 'hidden']) as
        | ImmutableMap<string, boolean>
        | undefined,
  );
  const useMyArchive = useAppSelector(
    (state) => state.local_settings.get('use_my_archive', false) as boolean,
  );
  const showNotificationCount = useAppSelector(
    (state) =>
      state.local_settings.getIn(['notifications', 'tab_badge']) as boolean,
  );
  const announcementsCount = useAppSelector(
    (state) => state.boardAnnouncements.unreadCount,
  );

  useEffect(() => {
    if (signedIn && boardAnnouncementsEnabled) {
      void dispatch(fetchBoardAnnouncementsUnreadCount());
    }
  }, [dispatch, signedIn]);

  const links: Partial<
    Record<
      NavigationPanelItem,
      {
        to: string;
        icon: Icon;
        activePaths?: string[];
        badgeCount?: number;
      }
    >
  > = {};

  if (trendsEnabled) links.explore = { to: '/explore', icon: TrendUpIcon };
  if (
    federatedTimelineEnabled &&
    canViewFeed(signedIn, permissions, remoteLiveFeedAccess)
  ) {
    links.federated = { to: '/public', icon: GlobeIcon };
  }
  if (
    localTimelineEnabled &&
    canViewFeed(signedIn, permissions, localLiveFeedAccess)
  ) {
    links.local = { to: '/public/local', icon: UsersIcon };
  }
  if (signedIn) {
    links.home = { to: '/home', icon: HouseIcon };
    links.notifications = {
      to: '/notifications',
      icon: BellIcon,
      badgeCount: showNotificationCount ? notificationsCount : 0,
    };
    links.direct = { to: '/conversations', icon: ChatCircleDotsIcon };
    if (useMyArchive) {
      links.my_archive = {
        to: '/favourites',
        icon: BankIcon,
        activePaths: ['/favourites', '/bookmarks', '/reactions', '/clips'],
      };
    } else {
      links.favourites = { to: '/favourites', icon: HeartIcon };
      links.bookmarks = { to: '/bookmarks', icon: BookmarkSimpleIcon };
    }
    if (collectionsEnabled && account) {
      links.collections = {
        to: `/@${account.acct}/collections`,
        icon: CirclesFourIcon,
      };
    }
    if (boardAnnouncementsEnabled) {
      links.board_announcements = {
        to: '/board_announcements',
        icon: MegaphoneIcon,
        badgeCount: announcementsCount,
      };
    }
  }

  return getRedesignNavigationKeys({
    order: order?.toArray(),
    hidden: hidden?.toObject(),
    available: Object.keys(links),
    showHidden: showHidden || mobile,
  }).map((key) => {
    const link = links[key];
    if (!link) return null;

    return (
      <NavigationLink
        key={key}
        to={link.to}
        exact={key === 'federated'}
        iconComponent={link.icon}
        activePaths={link.activePaths}
        badgeCount={link.badgeCount}
      >
        {intl.formatMessage(navigationPanelItemMessages[key])}
      </NavigationLink>
    );
  });
};

export const SharlayanRedesignExtensions: React.FC = () => {
  const useMyArchive = useAppSelector(
    (state) => state.local_settings.get('use_my_archive', false) as boolean,
  );

  return (
    <ListSection
      id='sharlayan-extensions'
      title={
        <FormattedMessage
          id='navigation_bar.extensions'
          defaultMessage='Extensions'
        />
      }
    >
      <NavigationLink to='/drafts' iconComponent={FloppyDiskIcon}>
        <FormattedMessage id='navigation_bar.drafts' defaultMessage='Drafts' />
      </NavigationLink>
      {softHideDeletion && adminTimelineOwnerViewer && (
        <NavigationLink to='/rp_hidden' iconComponent={EyeSlashIcon}>
          <FormattedMessage
            id='navigation_bar.rp_hidden'
            defaultMessage='Deleted posts'
          />
        </NavigationLink>
      )}
      {!useMyArchive && (
        <NavigationLink to='/reactions' iconComponent={SmileyIcon}>
          <FormattedMessage
            id='navigation_bar.reactions'
            defaultMessage='Reactions'
          />
        </NavigationLink>
      )}
      <NavigationLink to='/scheduled' iconComponent={CalendarIcon}>
        <FormattedMessage
          id='navigation_bar.scheduled'
          defaultMessage='Scheduled posts'
        />
      </NavigationLink>
      {clipsEnabled && !useMyArchive && (
        <NavigationLink to='/clips' iconComponent={StackIcon}>
          <FormattedMessage id='navigation_bar.clips' defaultMessage='Clips' />
        </NavigationLink>
      )}
      {pagesEnabled && (
        <NavigationLink to='/pages' iconComponent={FileTextIcon}>
          <FormattedMessage id='navigation_bar.pages' defaultMessage='Pages' />
        </NavigationLink>
      )}
      {circlesEnabled && (
        <NavigationLink to='/circles' iconComponent={UsersIcon}>
          <FormattedMessage
            id='navigation_bar.circles'
            defaultMessage='Circles'
          />
        </NavigationLink>
      )}
    </ListSection>
  );
};

type Antenna = ImmutableMap<string, string>;

export const SharlayanRedesignAntennas: React.FC = () =>
  antennaEnabled ? <RedesignAntennas /> : null;

const RedesignAntennas: React.FC = () => {
  const dispatch = useAppDispatch();
  const antennas = useAppSelector(
    (state) => state.antennas as ImmutableMap<string, Antenna | false>,
  );

  useEffect(() => {
    void dispatch(fetchAntennas());
  }, [dispatch]);

  const orderedAntennas = antennas
    .filter((antenna): antenna is Antenna => !!antenna)
    .toList()
    .sort((a, b) => {
      const aLast = a.get('last_status_id');
      const bLast = b.get('last_status_id');
      if (aLast && bLast) return bLast.localeCompare(aLast);
      if (aLast) return -1;
      if (bLast) return 1;
      return (a.get('title') ?? '').localeCompare(b.get('title') ?? '');
    })
    .slice(0, 10);

  return (
    <ListSection
      id='sharlayan-antennas'
      title={
        <FormattedMessage
          id='navigation_bar.antennas'
          defaultMessage='Antennas'
        />
      }
    >
      <NavigationLink to='/antennas' exact iconComponent={RssSimpleIcon}>
        <FormattedMessage
          id='tabs_bar.followed_tags_view_all'
          defaultMessage='View all'
        />
      </NavigationLink>
      {orderedAntennas.map((antenna) => (
        <NavigationLink
          key={antenna.get('id')}
          to={`/antennas/${antenna.get('id')}`}
          iconComponent={RssSimpleIcon}
        >
          {antenna.get('title')}
        </NavigationLink>
      ))}
    </ListSection>
  );
};

export const SharlayanRedesignAccountMenuItems: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const items: MenuItem[] = [
    {
      to: '/mutes',
      text: intl.formatMessage({
        id: 'navigation_bar.mutes',
        defaultMessage: 'Muted users',
      }),
    },
    {
      to: '/domain_blocks',
      text: intl.formatMessage({
        id: 'navigation_bar.domain_blocks',
        defaultMessage: 'Blocked domains',
      }),
    },
    {
      href: '/filters',
      text: intl.formatMessage({
        id: 'navigation_bar.filters',
        defaultMessage: 'Muted words',
      }),
    },
    null,
    {
      text: intl.formatMessage({
        id: 'navigation_bar.app_settings',
        defaultMessage: 'App settings',
      }),
      action: () =>
        dispatch(openModal({ modalType: 'SETTINGS', modalProps: {} })),
    },
  ];

  extendSharlayanMoreMenuItems(
    items,
    intl.formatMessage,
    () =>
      dispatch(openModal({ modalType: 'ACCOUNT_SWITCHER', modalProps: {} })),
    driveEnabled,
  );

  return <LegacyDropdownMenuItems items={items} />;
};
