import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router';

import { fromJS } from 'immutable';
import type { Map as ImmutableMap } from 'immutable';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import { fetchAntennas } from '@/flavours/glitch/actions/antennas';
import { fetchBoardAnnouncementsUnreadCount } from '@/flavours/glitch/actions/board_announcements';
import { MobileNavigation } from '@/flavours/glitch/features/navigation_panel/mobile_nav';
import { PEMRISSION_VIEW_FEEDS } from '@/flavours/glitch/permissions';

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
  searchClick: vi.fn(),
  flags: {
    initialState: null,
    me: '1',
    chatEnabled: false,
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
    sso_redirect: undefined,
    registrationsOpen: false,
  },
  roleplay: {
    adminTimelineOwnerViewer: false,
    softHideDeletion: true,
  },
}));

let state: {
  local_settings: ImmutableMap<string, unknown>;
  boardAnnouncements: { unreadCount: number };
  antennas: ImmutableMap<string, unknown>;
  navigation: { isMobileMenuOpen: boolean };
  server: { server: { item: null } };
} = {
  local_settings: fromJS({}),
  boardAnnouncements: { unreadCount: 3 },
  antennas: fromJS({}),
  navigation: { isMobileMenuOpen: false },
  server: { server: { item: null } },
};

vi.mock('@/flavours/glitch/initial_state', () => context.flags);
vi.mock('@/flavours/glitch/sharlayan/roleplay', () => context.roleplay);
vi.mock('@/flavours/glitch/store', () => ({
  useAppDispatch: () => context.dispatch,
  useAppSelector: (selector: (value: typeof state) => unknown) =>
    selector(state),
}));
vi.mock('@/flavours/glitch/identity_context', () => ({
  useIdentity: () => ({
    signedIn: context.signedIn,
    permissions: context.permissions,
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
vi.mock('@/flavours/glitch/actions/server', () => ({
  fetchServer: vi.fn(() => ({ type: 'FETCH_SERVER' })),
}));
vi.mock('@/flavours/glitch/actions/modal', () => ({
  openModal: (payload: unknown) => ({ type: 'OPEN_MODAL', payload }),
}));
vi.mock('@/flavours/glitch/components/badge', () => ({
  Badge: ({ label }: { label: React.ReactNode }) => <span>{label}</span>,
}));
vi.mock('@/flavours/glitch/features/navigation_panel/list_section', () => ({
  ListSection: ({ children }: { children: React.ReactNode }) => (
    <li>
      <ul>{children}</ul>
    </li>
  ),
}));
vi.mock('@/flavours/glitch/components/menu', () => ({
  Menu: ({ children }: { children: React.ReactNode }) => children,
  MenuList: ({ children }: { children: React.ReactNode }) => children,
  MenuTrigger: () => null,
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

vi.mock('@/flavours/glitch/features/navigation_panel', () => ({
  NavigationPanel: () => null,
  handleSearchLinkClick: context.searchClick,
}));
vi.mock(
  '@/flavours/glitch/features/navigation_panel/account_menu_items',
  () => ({ AccountMenuItems: () => null }),
);
vi.mock('@/flavours/glitch/features/navigation_panel/header', () => ({
  LogoLockup: () => null,
}));
vi.mock('@/flavours/glitch/features/navigation_panel/mini_nav', () => ({
  AccountButton: () => null,
  MiniHomeLink: () => null,
  MiniMessagesLink: () => null,
  MiniNotificationsLink: () => null,
}));
vi.mock('@/flavours/glitch/features/compose/trigger', () => ({
  ComposeButton: () => null,
}));
vi.mock('@/flavours/glitch/hooks/useCloseOnHistoryBack', () => ({
  useCloseOnHistoryBack: () => undefined,
}));
vi.mock('@/flavours/glitch/selectors/notifications', () => ({
  selectUnreadNotificationGroupsCount: () => 0,
}));
vi.mock('@/flavours/glitch/components/avatar', () => ({
  Avatar: () => null,
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
      localLiveFeedAccess: 'public',
      trendsEnabled: true,
      pagesEnabled: true,
    });
    state = {
      local_settings: fromJS({ notifications: { tab_badge: true } }),
      boardAnnouncements: { unreadCount: 3 },
      antennas: fromJS({}),
      navigation: { isMobileMenuOpen: false },
      server: { server: { item: null } },
    };
  });

  afterEach(cleanup);

  it('replaces only the mobile search tab and preserves local labels and active links', () => {
    const Component = MobileNavigation;
    {
      const view = render(
        <MemoryRouter initialEntries={['/public/local']}>
          <IntlProvider locale='en'>
            <Component />
          </IntlProvider>
        </MemoryRouter>,
      );
      expect(
        screen.getByRole('link', { name: 'Search' }).getAttribute('href'),
      ).toBe('/explore');
      expect(screen.queryByRole('link', { name: 'Local' })).toBeNull();

      state.local_settings = fromJS({
        navigation_panel: {
          mobile_local_timeline: true,
          order: ['notifications', 'home'],
          hidden: { local: true },
        },
      });
      view.rerender(
        <MemoryRouter initialEntries={['/public/local']}>
          <IntlProvider locale='en'>
            <Component />
          </IntlProvider>
        </MemoryRouter>,
      );

      const local = screen.getByRole('link', { name: 'Local' });
      expect(local.getAttribute('href')).toBe('/public/local');
      expect(local.getAttribute('aria-current')).toBe('page');
      expect(local.querySelector('svg')).not.toBeNull();
      expect(screen.queryByRole('link', { name: 'Search' })).toBeNull();
      fireEvent.click(local);
      expect(context.searchClick).not.toHaveBeenCalled();
      view.unmount();
      state.local_settings = fromJS({});
    }
  });

  it('falls back to search when local access is disabled and retains the redesign search focus behavior', () => {
    state.local_settings = fromJS({
      navigation_panel: { mobile_local_timeline: true },
    });
    const Component = MobileNavigation;
    {
      for (const gate of ['feature', 'permission']) {
        context.flags.localTimelineEnabled = gate !== 'feature';
        context.flags.localLiveFeedAccess =
          gate === 'permission' ? 'disabled' : 'public';
        const view = render(
          <MemoryRouter>
            <IntlProvider locale='en'>
              <Component />
            </IntlProvider>
          </MemoryRouter>,
        );
        expect(
          screen.getByRole('link', { name: 'Search' }).getAttribute('href'),
        ).toBe('/explore');
        expect(screen.queryByRole('link', { name: 'Local' })).toBeNull();
        view.unmount();
      }
    }

    context.permissions = PEMRISSION_VIEW_FEEDS;
    const authorized = render(
      <MemoryRouter>
        <IntlProvider locale='en'>
          <MobileNavigation />
        </IntlProvider>
      </MemoryRouter>,
    );
    expect(
      screen.getByRole('link', { name: 'Local' }).getAttribute('href'),
    ).toBe('/public/local');
    authorized.unmount();

    context.permissions = 0;
    context.flags.trendsEnabled = false;
    const fallback = render(
      <MemoryRouter>
        <IntlProvider locale='en'>
          <MobileNavigation />
        </IntlProvider>
      </MemoryRouter>,
    );
    const search = screen.getByRole('link', { name: 'Search' });
    expect(search.getAttribute('href')).toBe('/search');
    fireEvent.click(search);
    expect(context.searchClick).toHaveBeenCalledOnce();
    fallback.unmount();
  });

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

    fireEvent.click(screen.getByRole('button', { name: 'Drive' }));
    expect(context.dispatch).toHaveBeenLastCalledWith({
      type: 'OPEN_MODAL',
      payload: { modalType: 'DRIVE_MANAGER', modalProps: {} },
    });
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

  it('connects custom mute screens, account switching, and app settings', () => {
    renderNavigation(<SharlayanRedesignAccountMenuItems />);

    expect(paths()).toEqual([
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

  it('hides the Drive button when its feature gate is off', () => {
    context.flags.driveEnabled = false;
    renderNavigation(<SharlayanRedesignExtensions />);

    expect(screen.queryByRole('button', { name: 'Drive' })).toBeNull();
  });
});
