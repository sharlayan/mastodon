import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router-dom';

import { fromJS } from 'immutable';

import { fireEvent, render, screen } from '@testing-library/react';
import { vi } from 'vitest';

import type { AccountStatusShape } from '@/flavours/glitch/models/status';
import { useAppSelector } from '@/flavours/glitch/store';
import type { RootState } from '@/flavours/glitch/store';

import { StatusRedesignHeader } from './header';
import { StatusMeta } from './meta';

vi.hoisted(() => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });
});

vi.mock('@/flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppSelector: vi.fn(),
}));
vi.mock('@/flavours/glitch/hooks/useAccount', () => ({
  useAccount: () => undefined,
}));
vi.mock('@/flavours/glitch/hooks/useAccountId', () => ({
  useCurrentAccountId: () => 'self',
}));
vi.mock('../avatar', () => ({ Avatar: () => null }));
vi.mock('../display_name', () => ({
  DisplayName: ({ account }: { account: { display_name: string } }) => (
    <span>{account.display_name}</span>
  ),
}));
vi.mock('../instance_badge', () => ({
  default: ({ instanceInfo }: { instanceInfo: { domain: string } }) => (
    <span data-testid='instance-badge'>{instanceInfo.domain}</span>
  ),
  isLocalInstanceDomain: (domain: string) => domain === 'local.test',
}));
vi.mock('../animated_number', () => ({
  AnimatedNumber: ({ value }: { value: number }) => value,
}));

const status = {
  id: 'post-1',
  account: {
    id: 'author',
    acct: 'author@remote.test',
    display_name: 'Author',
    username: 'author',
  },
  created_at: '2026-10-20T10:00:00Z',
  visibility: 'public',
  mentions: [],
  media_attachments: [],
  collapsed: false,
  local_only: true,
  instance_metadata: { domain: 'remote.test' },
  replies_count: 0,
  reblogs_count: 0,
  favourites_count: 0,
  quotes_count: 0,
} as unknown as AccountStatusShape;

function setSettings(settings = {}) {
  vi.mocked(useAppSelector).mockImplementation((selector) =>
    selector({
      local_settings: fromJS({
        status_icons: { local_only: true, visibility: true },
        show_instance_info: true,
        ...settings,
      }),
    } as unknown as RootState),
  );
}

function renderHeader(
  props: Partial<React.ComponentProps<typeof StatusRedesignHeader>> = {},
) {
  return render(
    <MemoryRouter>
      <IntlProvider locale='en'>
        <StatusRedesignHeader status={status} {...props} />
      </IntlProvider>
    </MemoryRouter>,
  );
}

describe('redesign status header extensions', () => {
  beforeEach(() => {
    setSettings();
  });

  it('preserves the handle preference and removes the hidden description reference', () => {
    setSettings({ hide_timeline_account_handle: true });
    renderHeader();
    expect(screen.queryByText('@author@remote.test')).toBeNull();
    expect(
      screen
        .getByRole('link', { name: 'Author' })
        .hasAttribute('aria-describedby'),
    ).toBe(false);
  });

  it('shows local-only and remote instance information', () => {
    renderHeader();
    expect(
      screen.getByLabelText('Only visible from your instance'),
    ).not.toBeNull();
    expect(screen.getByTestId('instance-badge').textContent).toBe(
      'remote.test',
    );
    expect(screen.getByText('@author@remote.test')).not.toBeNull();
  });

  it.each([
    [{ show_instance_info: false }, false, 'remote.test'],
    [{}, false, 'local.test'],
    [{ show_instance_info_local: true }, true, 'local.test'],
  ])(
    'honors the instance visibility preferences',
    (settings, visible, domain) => {
      setSettings(settings);
      renderHeader({ status: { ...status, instance_metadata: { domain } } });
      expect(!!screen.queryByTestId('instance-badge')).toBe(visible);
    },
  );

  it('keeps the collapsed header and exposes its expand action while hiding instance details', () => {
    setSettings({ collapsed: { enabled: true } });
    const onCollapsedChange = vi.fn();
    renderHeader({ collapsed: true, onCollapsedChange });
    expect(screen.getByText('Author')).not.toBeNull();
    expect(screen.queryByTestId('instance-badge')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Uncollapse' }));
    expect(onCollapsedChange).toHaveBeenCalledWith(false);
  });

  it('labels Circle scope without describing it as a direct message', () => {
    renderHeader({
      status: {
        ...status,
        visibility: 'direct',
        limited_scope: 'circle',
        mentions: [{ id: 'self', acct: 'self', username: 'self', url: '' }],
      },
    });
    expect(screen.getByText('Circle')).not.toBeNull();
    expect(screen.queryByText(/to You/)).toBeNull();
  });

  it('honors disabled local-only and visibility indicators', () => {
    setSettings({ status_icons: { local_only: false, visibility: false } });
    renderHeader({ status: { ...status, limited_scope: 'circle' } });
    expect(
      screen.queryByLabelText('Only visible from your instance'),
    ).toBeNull();
    expect(screen.queryByText('Circle')).toBeNull();
  });

  it('preserves the edited marker', () => {
    renderHeader({ status: { ...status, edited_at: '2026-10-20T11:00:00Z' } });
    expect(screen.getByTitle(/^Edited /).textContent).toContain('*');
  });

  it('keeps the deleted badge visible in a collapsed header with indicators disabled', () => {
    setSettings({ status_icons: {} });
    renderHeader({ status: { ...status, rp_hidden: true }, collapsed: true });
    expect(screen.getByText('Deleted')).not.toBeNull();
  });

  it.each([false, undefined])(
    'does not mark a visible post as deleted (%s)',
    (rp_hidden) => {
      renderHeader({ status: { ...status, rp_hidden } });
      expect(screen.queryByText('Deleted')).toBeNull();
    },
  );
});

describe('redesign detailed status scope', () => {
  it.each([
    ['direct', 'circle', 'Circle'],
    ['unlisted', undefined, 'Quiet public'],
  ] as const)(
    'renders %s/%s scope and local-only separately',
    (visibility, limited_scope, label) => {
      render(
        <MemoryRouter>
          <IntlProvider locale='en'>
            <StatusMeta status={{ ...status, visibility, limited_scope }} />
          </IntlProvider>
        </MemoryRouter>,
      );
      expect(screen.getByText(label)).not.toBeNull();
      expect(screen.getByText('Local-only')).not.toBeNull();
    },
  );
});
