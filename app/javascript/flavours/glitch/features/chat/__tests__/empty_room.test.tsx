import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import { createMemoryHistory } from 'history';

import { IdentityContext } from 'flavours/glitch/identity_context';
import type * as InitialState from 'flavours/glitch/initial_state';

import { Chat } from '../index';
import { emitChatStreamEvent } from '../stream';

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
  ColumnHeader: () => null,
}));
vi.mock(
  'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container',
  () => ({ default: () => null }),
);
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const account = (id: string, displayName: string) => ({
  id,
  acct: id,
  display_name: displayName,
  avatar: `/avatars/${id}.png`,
  avatar_static: `/avatars/${id}.png`,
});
const mine = account('me', 'Alice');
const bob = account('bob', 'Bob');

const NO_MESSAGES = 'No messages yet.';
const SEND_FIRST = 'Send the first one.';
const INVITES =
  'People you invite join once they accept. You can see who hasn’t yet under Members in the ⋯ menu.';

const room = (extra: object = {}) => ({
  id: 'room',
  type: 'group',
  title: 'Hikers',
  description: null,
  unread: false,
  muted: false,
  archived: false,
  current_role: 'owner',
  accounts: [mine],
  last_message: null,
  ...extra,
});
const message = (id: string, content: string) => ({
  id,
  conversation_id: 'room',
  content,
  created_at: '2026-11-04T00:00:00Z',
  edited_at: null,
  deleted_at: null,
  reply_to_id: null,
  account: bob,
  reactions: [],
  media_attachments: [],
  editable: true,
});

const respond = (
  conversation: object,
  messagesResponse: () => Promise<unknown>,
) => {
  api.get.mockImplementation((url: string) => {
    if (url === '/api/v1/chat/conversations')
      return Promise.resolve({ data: [conversation] });
    if (url === '/api/v1/chat/conversations/room')
      return Promise.resolve({ data: conversation });
    if (url.endsWith('/messages')) return messagesResponse();
    if (url === '/api/v1/chat/invitations')
      return Promise.resolve({ data: [] });
    if (url === '/api/v1/chat/settings')
      return Promise.resolve({
        data: {
          policy: 'everyone',
          allow_group_invites: true,
          notifications: true,
          max_group_members: 10,
          max_attachments: 4,
          federation_enabled: true,
          delete_window_hours: 24,
          soft_delete: false,
        },
      });
    return Promise.reject(new Error(`Unexpected GET ${url}`));
  });
};

const mount = () =>
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
        <Router
          history={createMemoryHistory({ initialEntries: ['/chat/room'] })}
        >
          <Route path='/chat/:conversationId?/:view?'>
            <Chat />
          </Route>
        </Router>
      </IdentityContext.Provider>
    </IntlProvider>,
  );

const settle = async () => {
  await act(async () => {
    await new Promise((resolve) => {
      setTimeout(resolve, 0);
    });
  });
};

const indicator = () => document.querySelector('.empty-column-indicator');

beforeEach(() => {
  vi.resetAllMocks();
  api.post.mockResolvedValue({ data: {} });
});
afterEach(cleanup);

describe('A room with no messages', () => {
  it('says so with the empty indicator of the other lists', async () => {
    respond(room(), () => Promise.resolve({ data: [] }));
    mount();

    await waitFor(() => {
      expect(indicator()?.textContent).toContain(NO_MESSAGES);
    });
    expect(
      indicator()?.closest('.chat-native__messages'),
      'it sits where the messages will be',
    ).toBeTruthy();
  });

  it('tells the owner of a group how invitations work', async () => {
    respond(room(), () => Promise.resolve({ data: [] }));
    mount();

    await waitFor(() => {
      expect(indicator()?.textContent).toContain(SEND_FIRST);
    });
    expect(indicator()?.textContent).toContain(INVITES);
  });

  it('does not tell a member about invitations they cannot see', async () => {
    respond(room({ current_role: 'member' }), () =>
      Promise.resolve({ data: [] }),
    );
    mount();

    await waitFor(() => {
      expect(indicator()?.textContent).toContain(SEND_FIRST);
    });
    expect(indicator()?.textContent).not.toContain(INVITES);
  });

  it('does not talk about invitations in a direct chat', async () => {
    respond(room({ type: 'direct', title: null, accounts: [mine, bob] }), () =>
      Promise.resolve({ data: [] }),
    );
    mount();

    await waitFor(() => {
      expect(indicator()?.textContent).toContain(SEND_FIRST);
    });
    expect(indicator()?.textContent).not.toContain(INVITES);
  });

  it('does not suggest sending where nothing can be sent', async () => {
    respond(room({ archived: true }), () => Promise.resolve({ data: [] }));
    mount();

    await waitFor(() => {
      expect(indicator()?.textContent).toContain(NO_MESSAGES);
    });
    expect(indicator()?.textContent).not.toContain(SEND_FIRST);
    expect(indicator()?.textContent).not.toContain(INVITES);
  });

  it('does not suggest sending to a suspended account', async () => {
    respond(
      room({
        type: 'direct',
        title: null,
        accounts: [mine, { ...bob, suspended: true }],
      }),
      () => Promise.resolve({ data: [] }),
    );
    mount();

    await waitFor(() => {
      expect(indicator()?.textContent).toContain(NO_MESSAGES);
    });
    expect(indicator()?.textContent).not.toContain(SEND_FIRST);
  });

  it('stays away while the messages are still loading', async () => {
    let finish: (value: unknown) => void = () => undefined;
    respond(
      room(),
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    );
    mount();
    await settle();

    expect(document.querySelector('form.chat-native__composer')).toBeTruthy();
    expect(indicator()).toBeNull();

    await act(async () => {
      finish({ data: [] });
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(indicator()).toBeTruthy();
    });
  });

  it('stays away when the messages could not be loaded', async () => {
    respond(room(), () => Promise.reject(new Error('offline')));
    mount();

    await screen.findByRole('alert');
    await settle();

    expect(indicator()).toBeNull();
  });

  it('stays away from a room that has messages', async () => {
    respond(room(), () =>
      Promise.resolve({ data: [message('1', 'Hello there')] }),
    );
    mount();

    await screen.findByText('Hello there');
    await settle();

    expect(indicator()).toBeNull();
  });

  it('stays away when a first page arrives after the room looked empty', async () => {
    let finish: (value: unknown) => void = () => undefined;
    respond(
      room(),
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    );
    mount();
    await settle();

    await act(async () => {
      finish({
        data: Array.from({ length: 40 }, (_, index) =>
          message(String(index + 1), `Message ${index + 1}`),
        ),
      });
      await Promise.resolve();
    });

    await screen.findByText('Message 40');
    expect(indicator()).toBeNull();
  });

  it('waits for the room itself, so that its advice does not change', async () => {
    let finish: (value: unknown) => void = () => undefined;
    const details = new Promise((resolve) => {
      finish = resolve;
    });
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations') return details;
      if (url === '/api/v1/chat/conversations/room') return details;
      if (url.endsWith('/messages')) return Promise.resolve({ data: [] });
      if (url === '/api/v1/chat/invitations')
        return Promise.resolve({ data: [] });
      return Promise.resolve({ data: {} });
    });
    mount();
    await settle();

    expect(indicator()).toBeNull();

    await act(async () => {
      finish({ data: [room()] });
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(indicator()?.textContent).toContain(INVITES);
    });
  });

  it('stays away when only older pages are left to show', async () => {
    const page = Array.from({ length: 40 }, (_, index) =>
      message(String(index + 1), `Message ${index + 1}`),
    );
    respond(room(), () => Promise.resolve({ data: page }));
    mount();
    await screen.findByText('Message 40');

    act(() => {
      page.forEach(({ id }) => {
        emitChatStreamEvent({
          event: 'chat.message_hide',
          payload: { id, conversation_id: 'room' },
        });
      });
    });

    expect(screen.queryByText('Message 40')).toBeNull();
    expect(indicator()).toBeNull();
  });

  it('goes as soon as the first message comes over the stream', async () => {
    respond(room(), () => Promise.resolve({ data: [] }));
    mount();
    await waitFor(() => {
      expect(indicator()).toBeTruthy();
    });

    act(() => {
      emitChatStreamEvent({
        event: 'chat.message',
        payload: message('1', 'First!'),
      });
    });

    expect(screen.getByText('First!')).toBeTruthy();
    expect(indicator()).toBeNull();
  });

  it('adds no request to find out who was invited', async () => {
    respond(room(), () => Promise.resolve({ data: [] }));
    mount();
    await waitFor(() => {
      expect(indicator()).toBeTruthy();
    });
    await settle();

    const asked = api.get.mock.calls.map(([url]) => url as string);
    expect(asked.filter((url) => url.endsWith('/messages'))).toHaveLength(1);
    expect(asked.filter((url) => url.includes('/members'))).toEqual([]);
    expect(
      api.get.mock.calls.filter(
        ([url, config]) =>
          url === '/api/v1/chat/invitations' &&
          (config as { params?: { direction?: string } } | undefined)?.params
            ?.direction === 'sent',
      ),
    ).toEqual([]);
  });
});
