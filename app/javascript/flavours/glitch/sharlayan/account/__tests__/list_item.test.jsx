import { IntlProvider } from 'react-intl';

import { MemoryRouter } from 'react-router-dom';

import { cleanup, render, within } from '@testing-library/react';

let sharlayanAccountBioHtml;
let AccountListItem;
let AccountNumberFields;
let AccountListHeader;
let LegacyActionBar;

const mocks = vi.hoisted(() => ({
  account: undefined,
  dispatch: vi.fn(),
}));

vi.mock('flavours/glitch/hooks/useAccount', () => ({
  useAccount: () => mocks.account,
}));
vi.mock('flavours/glitch/hooks/useRelationship', () => ({
  useRelationship: () => null,
}));
vi.mock('flavours/glitch/hooks/useAccountId', () => ({
  useCurrentAccountId: () => null,
}));
vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal()),
  useAppDispatch: () => mocks.dispatch,
}));
vi.mock('flavours/glitch/components/avatar', () => ({ Avatar: () => null }));
vi.mock('flavours/glitch/components/follow_button', () => ({ FollowButton: () => null }));
vi.mock('flavours/glitch/components/emoji/html', () => ({ EmojiHTML: () => null }));

const account = (overrides = {}) => ({
  note_emojified: '<p>emojified</p>',
  note_plain: 'hello world bio text',
  ...overrides,
});

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ sharlayanAccountBioHtml } = await import('../list_item'));
  ({ AccountListItem } = await import('flavours/glitch/components/account_list_item'));
  ({ AccountNumberFields } = await import('flavours/glitch/components/account_header/number_fields'));
  ({ AccountListHeader } = await import('flavours/glitch/features/followers/components/header'));
  ({ ActionBar: LegacyActionBar } = await import('flavours/glitch/features/account/components/action_bar'));
}, 30_000);

describe('sharlayanAccountBioHtml', () => {
  it('returns the emojified note when no character limit is set', () => {
    expect(sharlayanAccountBioHtml(account())).toBe('<p>emojified</p>');
  });

  it('truncates the plain note with an ellipsis past the limit', () => {
    expect(sharlayanAccountBioHtml(account(), 5)).toBe('hello…');
  });

  it('keeps the full plain note within the limit and escapes it', () => {
    expect(sharlayanAccountBioHtml(account({ note_plain: 'a<b>' }), 100)).toBe(
      'a&lt;b&gt;',
    );
  });

  it('handles a null plain note', () => {
    expect(sharlayanAccountBioHtml(account({ note_plain: null }), 100)).toBe('');
  });
});


afterEach(() => {
  cleanup();
});

describe('account follower counts', () => {
  it('keeps hidden values out of profile, list item, and list total text and attributes', () => {
    for (const [count, text, hint] of [[-1, '-', null], [0, '0', '0'], [1234, '1.2K', '1,234']]) {
      mocks.account = {
        id: '1',
        acct: 'alice',
        username: 'alice',
        get: (key) => mocks.account[key],
        display_name_html: 'Alice',
        created_at: '2026-01-01T00:00:00Z',
        fields: [],
        note: '',
        following_count: 10,
        followers_count: count,
        statuses_count: 20,
      };
      const { getByTestId, container, unmount } = render(
        <IntlProvider locale='en'>
          <MemoryRouter>
            <div data-testid='legacy-profile'><LegacyActionBar account={mocks.account} /></div>
            <div data-testid='profile'><AccountNumberFields accountId='1' /></div>
            <div data-testid='list-item'><AccountListItem accountId='1' stats={['followers']} /></div>
            <div data-testid='total'>
              <AccountListHeader accountId='1' total={count} titleText={{ id: 'account.followers', defaultMessage: 'Followers' }} />
            </div>
          </MemoryRouter>
        </IntlProvider>,
      );

      for (const surface of ['profile', 'list-item']) {
        const item = within(getByTestId(surface)).getByText('Followers').closest('li');
        expect(item.textContent).toBe(`Followers${text}`);
        expect(item.getAttribute('title')).toBe(hint);
      }
      expect(within(getByTestId('legacy-profile')).getByText('Followers').closest('a').textContent).toBe(`Followers${hint ?? '-'}`);
      const total = within(getByTestId('total')).queryByRole('heading', { level: 2 });
      if (count > 0) expect(total.textContent).toBe('1,234 accounts');
      else expect(total).toBeNull();
      expect(container.textContent).not.toContain('-1');
      for (const element of container.querySelectorAll('[title], [aria-label]')) {
        expect(element.getAttribute('title')).not.toBe('-1');
        expect(element.getAttribute('aria-label')).not.toBe('-1');
      }
      unmount();
    }
  });
});
