import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { createMemoryHistory } from 'history';

import { IdentityContext } from 'flavours/glitch/identity_context';
import type * as InitialState from 'flavours/glitch/initial_state';

import { Chat } from '../index';

const api = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  patch: vi.fn(),
  delete: vi.fn(),
}));
vi.mock('flavours/glitch/api', () => ({ default: () => api }));
vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<typeof InitialState>()),
  me: 'me',
}));
vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => vi.fn(),
  useAppSelector: () => false,
}));
vi.mock('flavours/glitch/components/dropdown_menu', () => ({
  Dropdown: () => null,
}));
vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: ({ extraButton }: { extraButton?: React.ReactNode }) => (
    <header>{extraButton}</header>
  ),
}));
vi.mock(
  'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container',
  () => ({ default: () => null }),
);
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const account = (id: string, displayName: string) => ({
  id,
  acct: `${id}@remote.test`,
  display_name: displayName,
  avatar: `/avatars/${id}.png`,
  avatar_static: `/avatars/${id}.png`,
});
const mine = { ...account('me', 'Alice'), acct: 'alice' };
const bob = account('bob', 'Bob');
const carol = account('carol', 'Carol');
const room = (id: string, type: 'direct' | 'group', title: string | null) => ({
  id,
  type,
  title,
  description: null,
  unread: false,
  muted: false,
  archived: false,
  current_role: type === 'group' ? 'owner' : 'member',
  accounts: type === 'group' ? [mine, carol] : [mine, bob],
  last_message: null,
});
const responses: Record<string, unknown> = {
  '/api/v1/chat/conversations': [
    room('direct-chat', 'direct', null),
    room('group-chat', 'group', 'Book club'),
  ],
  '/api/v1/chat/conversations/group-chat': room(
    'group-chat',
    'group',
    'Book club',
  ),
  '/api/v1/chat/conversations/group-chat/messages': [],
  '/api/v1/chat/invitations': [],
  '/api/v1/chat/settings': {
    policy: 'everyone',
    allow_group_invites: true,
    notifications: true,
    max_group_members: 10,
    max_attachments: 4,
    federation_enabled: true,
    delete_window_hours: 24,
    soft_delete: false,
  },
  '/api/v2/search': { accounts: [bob] },
  '/api/v1/chat/messages/search': [
    {
      id: 'found',
      conversation_id: 'direct-chat',
      content: 'The word you looked for',
      created_at: '2026-11-04T00:00:00Z',
      edited_at: null,
      deleted_at: null,
      reply_to_id: null,
      account: bob,
      reactions: [],
      media_attachments: [],
    },
  ],
};

const mountAt = (path: string) =>
  render(
    <IntlProvider locale='en'>
      <IdentityContext.Provider
        value={{
          signedIn: true,
          permissions: 0,
          accountId: 'me',
          disabledAccountId: undefined,
        }}
      >
        <Router history={createMemoryHistory({ initialEntries: [path] })}>
          <Route path='/chat/:conversationId?/:view?'>
            <Chat />
          </Route>
        </Router>
      </IdentityContext.Provider>
    </IntlProvider>,
  );

const pictureOf = (element: Element | null) =>
  element?.querySelector('.account__avatar img')?.getAttribute('src');
const closestTo = (text: string, selector: string) =>
  screen.getByText(text).closest(selector);

// Finds Bob among the results and picks him, checking both places he shows up in.
const expectPictureWhileChoosingBob = async () => {
  fireEvent.change(screen.getByPlaceholderText('Search for an account'), {
    target: { value: 'bob' },
  });

  const result = (await screen.findByText('Bob')).closest('button');
  expect(pictureOf(result)).toBe('/avatars/bob.png');
  expect(result?.querySelector('a')).toBeNull();
  expect(closestTo('@bob@remote.test', 'button')).toBe(result);

  if (result) fireEvent.click(result);

  const card = closestTo('Bob', '.chat-native__account-card');
  expect(pictureOf(card)).toBe('/avatars/bob.png');
  expect(card?.querySelector('a')).toBeNull();
};

beforeEach(() => {
  vi.resetAllMocks();
  api.get.mockImplementation((url: string) => {
    if (url in responses) return Promise.resolve({ data: responses[url] });
    throw new Error(`Unexpected GET ${url}`);
  });
  api.post.mockResolvedValue({ data: {} });
});
afterEach(cleanup);

describe('Chat account pictures', () => {
  it('shows who is found and chosen for a direct chat', async () => {
    mountAt('/chat/new');
    await screen.findByPlaceholderText('Search for an account');

    await expectPictureWhileChoosingBob();
  });

  it('shows who is found and chosen for a new group', async () => {
    mountAt('/chat/new');
    fireEvent.click(
      await screen.findByRole('button', { name: 'Create a group' }),
    );

    await expectPictureWhileChoosingBob();
  });

  it('shows who is found and chosen when inviting to a group', async () => {
    mountAt('/chat/group-chat/members');
    await screen.findByPlaceholderText('Search for an account');

    await expectPictureWhileChoosingBob();
  });

  it('shows who wrote a message found by search', async () => {
    mountAt('/chat');
    fireEvent.click(
      await screen.findByRole('button', { name: 'Search messages' }),
    );
    const search = screen.getByPlaceholderText('Search messages');
    fireEvent.change(search, { target: { value: 'word' } });
    fireEvent.submit(search.closest('form') as HTMLFormElement);

    const result = (await screen.findByText('The word you looked for')).closest(
      'button',
    );
    expect(pictureOf(result)).toBe('/avatars/bob.png');
    expect(result?.querySelector('a')).toBeNull();
  });

  it('shows who sent an invitation', async () => {
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/invitations')
        return Promise.resolve({
          data: [
            {
              id: 'invitation',
              conversation: room('invited', 'group', 'Garden club'),
              inviter: bob,
            },
          ],
        });
      if (url in responses) return Promise.resolve({ data: responses[url] });
      throw new Error(`Unexpected GET ${url}`);
    });

    mountAt('/chat');
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );

    await screen.findByText('Garden club');
    const row = closestTo('Garden club', '.chat-native__invitation');
    expect(pictureOf(row)).toBe('/avatars/bob.png');
    expect(row?.querySelector('a')).toBeNull();
  });

  it('shows the other person of a direct chat, and a group as a group', async () => {
    mountAt('/chat');

    const direct = (await screen.findByText('Bob')).closest('button');
    expect(pictureOf(direct)).toBe('/avatars/bob.png');
    expect(direct?.querySelector('a')).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Your groups' }));

    const group = (await screen.findByText('Book club')).closest('button');
    expect(group?.querySelector('.account__avatar')).toBeNull();
    expect(group?.querySelector('.chat-native__room-picture svg')).toBeTruthy();
  });

  it('keeps the accessible name of a result to the names', async () => {
    mountAt('/chat/new');
    fireEvent.change(
      await screen.findByPlaceholderText('Search for an account'),
      { target: { value: 'bob' } },
    );

    expect(
      await screen.findByRole('button', { name: /^Bob\s*@bob@remote\.test$/ }),
    ).toBeTruthy();
  });
});
