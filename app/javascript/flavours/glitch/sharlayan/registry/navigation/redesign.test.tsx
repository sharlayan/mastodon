import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router';

import { fromJS } from 'immutable';
import type { Map as ImmutableMap } from 'immutable';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { fetchAntennas } from '@/flavours/glitch/actions/antennas';
import { fetchBoardAnnouncementsUnreadCount } from '@/flavours/glitch/actions/board_announcements';
import {
  EXTRA_PERMISSION_VIEW_ADMIN_TIMELINE,
  EXTRA_PERMISSION_VIEW_FOLLOWERS_ADMIN_TIMELINE,
  PERMISSION_ADMINISTRATOR,
  PERMISSION_VIEW_DASHBOARD,
} from '@/flavours/glitch/permissions';

import {
  SharlayanRedesignAccountMenuItems,
  SharlayanRedesignAntennas,
  SharlayanRedesignExtensions,
  SharlayanRedesignPrimaryNavigation,
} from './redesign';

const context = vi.hoisted(() => ({
  dispatch: vi.fn(),
  mobile: false,
  signedIn: true,
  permissions: 0,
  extraPermissions: 0,
  flags: {
    antennaEnabled: true,
    boardAnnouncementsEnabled: true,
    circlesEnabled: true,
    clipsEnabled: true,
    collectionsEnabled: true,
    driveEnabled: true,
    federatedTimelineEnabled: true,
    localTimelineEnabled: true,
    localLiveFeedAccess: 'public',
    remoteLiveFeedAccess: 'authenticated',
    pagesEnabled: true,
    trendsEnabled: true,
  },
  roleplay: {
    adminTimelineEnabled: false,
    adminTimelineOwnerViewer: false,
    softHideDeletion: true,
  },
}));

let state: {
  local_settings: ImmutableMap<string, unknown>;
  boardAnnouncements: { unreadCount: number };
  antennas: ImmutableMap<string, unknown>;
} = {
  local_settings: fromJS({}),
  boardAnnouncements: { unreadCount: 3 },
  antennas: fromJS({}),
};

vi.mock('@/flavours/glitch/initial_state', () => context.flags);
vi.mock('@/flavours/glitch/sharlayan/roleplay', async () => {
  const { canViewAdminTimeline } =
    await import('@/flavours/glitch/permissions');

  return {
    get adminTimelineOwnerViewer() {
      return context.roleplay.adminTimelineOwnerViewer;
    },
    get softHideDeletion() {
      return context.roleplay.softHideDeletion;
    },
    canUseAdminTimeline: (permissions: number, extraPermissions: number) =>
      context.roleplay.adminTimelineEnabled &&
      canViewAdminTimeline(permissions, extraPermissions),
  };
});
vi.mock('@/flavours/glitch/store', () => ({
  useAppDispatch: () => context.dispatch,
  useAppSelector: (selector: (value: typeof state) => unknown) =>
    selector(state),
}));
vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({
    signedIn: context.signedIn,
    permissions: context.permissions,
    extraPermissions: context.extraPermissions,
    accountId: context.signedIn ? '1' : undefined,
  }),
}));
vi.mock('@/flavours/glitch/hooks/useAccount', () => ({
  useAccount: () => ({ acct: 'alice' }),
}));
vi.mock('@/flavours/glitch/features/ui/hooks/useBreakpoint', () => ({
  useBreakpoint: () => context.mobile,
}));
vi.mock('@/flavours/glitch/actions/antennas', () => ({
  fetchAntennas: vi.fn(() => ({ type: 'FETCH_ANTENNAS' })),
}));
vi.mock('@/flavours/glitch/actions/board_announcements', () => ({
  fetchBoardAnnouncementsUnreadCount: vi.fn(() => ({
    type: 'FETCH_ANNOUNCEMENTS',
  })),
}));
vi.mock('@/flavours/glitch/actions/modal', () => ({
  openModal: (payload: unknown) => ({ type: 'OPEN_MODAL', payload }),
}));
vi.mock('@/flavours/glitch/components/badge', () => ({
  Badge: ({ label }: { label: React.ReactNode }) => <span>{label}</span>,
}));
vi.mock(
  '@/flavours/glitch/features/navigation_panel/redesign/list_section',
  () => ({
    ListSection: ({ children }: { children: React.ReactNode }) => (
      <li>
        <ul>{children}</ul>
      </li>
    ),
  }),
);
vi.mock('@/flavours/glitch/components/menu', () => ({
  LegacyDropdownMenuItems: ({
    items,
  }: {
    items: ({
      text: string;
      to?: string;
      href?: string;
      action?: () => void;
    } | null)[];
  }) =>
    items.map((item, index) => {
      if (!item) return <hr key={index} />;
      if (item.action)
        return (
          <button key={item.text} type='button' onClick={item.action}>
            {item.text}
          </button>
        );
      return (
        <a key={item.text} href={item.to ?? item.href}>
          {item.text}
        </a>
      );
    }),
}));

const renderNavigation = (element: React.ReactNode) =>
  render(
    <MemoryRouter>
      <IntlProvider locale='en'>
        <ul>{element}</ul>
      </IntlProvider>
    </MemoryRouter>,
  );

const paths = () =>
  screen.queryAllByRole('link').map((link) => link.getAttribute('href'));

describe('Sharlayan redesign navigation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    context.mobile = false;
    context.signedIn = true;
    context.permissions = 0;
    context.extraPermissions = 0;
    context.roleplay.adminTimelineEnabled = false;
    context.roleplay.adminTimelineOwnerViewer = false;
    Object.assign(context.flags, {
      antennaEnabled: true,
      boardAnnouncementsEnabled: true,
      circlesEnabled: true,
      clipsEnabled: true,
      collectionsEnabled: true,
      driveEnabled: true,
      federatedTimelineEnabled: true,
      localTimelineEnabled: true,
      pagesEnabled: true,
    });
    state = {
      local_settings: fromJS({ notifications: { tab_badge: true } }),
      boardAnnouncements: { unreadCount: 3 },
      antennas: fromJS({}),
    };
  });

  afterEach(cleanup);

  it('preserves saved ordering and hidden items while keeping announcements visible', () => {
    state.local_settings = fromJS({
      navigation_panel: {
        order: ['direct', 'home', 'unknown', 'bookmarks'],
        hidden: { home: true, board_announcements: true },
      },
    });
    renderNavigation(
      <SharlayanRedesignPrimaryNavigation notificationsCount={4} />,
    );

    expect(paths().slice(0, 2)).toEqual(['/conversations', '/bookmarks']);
    expect(paths()).not.toContain('/home');
    expect(paths()).toContain('/board_announcements');
    expect(fetchBoardAnnouncementsUnreadCount).toHaveBeenCalledOnce();
  });

  it('restores hidden items in the mobile drawer without bypassing feature gates', () => {
    context.flags.boardAnnouncementsEnabled = false;
    context.flags.localTimelineEnabled = false;
    state.local_settings = fromJS({
      navigation_panel: { hidden: { home: true } },
    });
    renderNavigation(
      <SharlayanRedesignPrimaryNavigation notificationsCount={0} showHidden />,
    );

    expect(paths()).toContain('/home');
    expect(paths()).not.toContain('/public/local');
    expect(paths()).not.toContain('/board_announcements');
    expect(fetchBoardAnnouncementsUnreadCount).not.toHaveBeenCalled();
  });

  it('keeps authenticated-only feeds and account navigation hidden when signed out', () => {
    context.signedIn = false;
    renderNavigation(
      <SharlayanRedesignPrimaryNavigation notificationsCount={0} />,
    );

    expect(paths()).toEqual(['/explore', '/public/local']);
    expect(fetchBoardAnnouncementsUnreadCount).not.toHaveBeenCalled();
  });

  it.each([
    [PERMISSION_ADMINISTRATOR, 0],
    [0, EXTRA_PERMISSION_VIEW_ADMIN_TIMELINE],
    [0, EXTRA_PERMISSION_VIEW_FOLLOWERS_ADMIN_TIMELINE],
  ])(
    'shows the management timeline for authorized permissions %i and extra permissions %i',
    (permissions, extraPermissions) => {
      context.permissions = permissions;
      context.extraPermissions = extraPermissions;
      context.roleplay.adminTimelineEnabled = true;
      renderNavigation(
        <SharlayanRedesignPrimaryNavigation notificationsCount={0} />,
      );

      expect(
        screen
          .getByRole('link', { name: 'Management timeline' })
          .getAttribute('href'),
      ).toBe('/timelines/admin');
    },
  );

  it.each([
    {
      signedIn: false,
      enabled: true,
      permissions: 0,
      extraPermissions: EXTRA_PERMISSION_VIEW_ADMIN_TIMELINE,
    },
    {
      signedIn: true,
      enabled: false,
      permissions: PERMISSION_ADMINISTRATOR,
      extraPermissions: 0,
    },
    { signedIn: true, enabled: true, permissions: 0, extraPermissions: 0 },
    {
      signedIn: true,
      enabled: true,
      permissions: PERMISSION_VIEW_DASHBOARD,
      extraPermissions: 0,
    },
  ])(
    'keeps the management timeline gated with signedIn=$signedIn, enabled=$enabled, permissions=$permissions, extraPermissions=$extraPermissions',
    ({ signedIn, enabled, permissions, extraPermissions }) => {
      context.signedIn = signedIn;
      context.permissions = permissions;
      context.extraPermissions = extraPermissions;
      context.roleplay.adminTimelineEnabled = enabled;
      renderNavigation(
        <SharlayanRedesignPrimaryNavigation
          notificationsCount={0}
          showHidden
        />,
      );

      expect(paths()).not.toContain('/timelines/admin');
    },
  );

  it('preserves management timeline ordering and the saved hidden choice', () => {
    context.extraPermissions = EXTRA_PERMISSION_VIEW_FOLLOWERS_ADMIN_TIMELINE;
    context.roleplay.adminTimelineEnabled = true;
    state.local_settings = fromJS({
      navigation_panel: {
        order: ['admin_timeline', 'home'],
        hidden: { admin_timeline: true },
      },
    });
    renderNavigation(
      <SharlayanRedesignPrimaryNavigation notificationsCount={0} />,
    );

    expect(paths()).not.toContain('/timelines/admin');
    cleanup();
    renderNavigation(
      <SharlayanRedesignPrimaryNavigation notificationsCount={0} showHidden />,
    );

    expect(paths()[0]).toBe('/timelines/admin');
  });

  it('uses My archive and preserves extension feature and role gates', () => {
    state.local_settings = fromJS({ use_my_archive: true });
    context.flags.pagesEnabled = false;
    context.flags.circlesEnabled = false;
    renderNavigation(
      <>
        <SharlayanRedesignPrimaryNavigation notificationsCount={0} />
        <SharlayanRedesignExtensions />
      </>,
    );

    expect(
      screen.getByRole('link', { name: 'My archive' }).getAttribute('href'),
    ).toBe('/favourites');
    expect(paths()).toContain('/drafts');
    expect(paths()).toContain('/scheduled');
    for (const path of [
      '/bookmarks',
      '/clips',
      '/reactions',
      '/pages',
      '/circles',
      '/rp_hidden',
    ]) {
      expect(paths()).not.toContain(path);
    }
  });

  it('shows gated extension routes when enabled and authorized', () => {
    context.roleplay.adminTimelineOwnerViewer = true;
    renderNavigation(<SharlayanRedesignExtensions />);

    expect(paths()).toEqual([
      '/drafts',
      '/rp_hidden',
      '/reactions',
      '/scheduled',
      '/clips',
      '/pages',
      '/circles',
    ]);
  });

  it('does not fetch antennas when disabled', () => {
    context.flags.antennaEnabled = false;
    renderNavigation(<SharlayanRedesignAntennas />);

    expect(fetchAntennas).not.toHaveBeenCalled();
    expect(paths()).toEqual([]);
  });

  it('retains the antenna overview and orders recent antennas first', () => {
    state.antennas = fromJS({
      one: { id: 'one', title: 'First', last_status_id: '100' },
      two: { id: 'two', title: 'Second', last_status_id: '200' },
    });
    renderNavigation(<SharlayanRedesignAntennas />);

    expect(fetchAntennas).toHaveBeenCalledOnce();
    expect(paths()).toEqual(['/antennas', '/antennas/two', '/antennas/one']);
  });

  it('connects Drive, custom mute screens, account switching, and app settings', () => {
    renderNavigation(<SharlayanRedesignAccountMenuItems />);

    expect(paths()).toEqual([
      '/drive',
      '/mutes',
      '/custom_emoji_mutes',
      '/reaction_mutes',
      '/domain_blocks',
      '/domain_mutes',
      '/filters',
    ]);
    fireEvent.click(screen.getByRole('button', { name: 'Switch account' }));
    expect(context.dispatch).toHaveBeenLastCalledWith({
      type: 'OPEN_MODAL',
      payload: { modalType: 'ACCOUNT_SWITCHER', modalProps: {} },
    });
    fireEvent.click(screen.getByRole('button', { name: 'App settings' }));
    expect(context.dispatch).toHaveBeenLastCalledWith({
      type: 'OPEN_MODAL',
      payload: { modalType: 'SETTINGS', modalProps: {} },
    });
  });

  it('hides Drive when its feature gate is off', () => {
    context.flags.driveEnabled = false;
    renderNavigation(<SharlayanRedesignAccountMenuItems />);

    expect(paths()).not.toContain('/drive');
  });
});
