import { useCallback } from 'react';

import { IntlProvider } from 'react-intl';

import type * as ReactRouterDom from 'react-router-dom';
import { Route, Router } from 'react-router-dom';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import { createMemoryHistory } from 'history';

import type { ColumnHeaderProps } from 'flavours/glitch/components/column/header';
import { IdentityContext } from 'flavours/glitch/identity_context';
import type * as InitialState from 'flavours/glitch/initial_state';
import type { MenuItem } from 'flavours/glitch/models/dropdown_menu';

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
// The surrounding column controls and global emoji picker require the app store;
// keep chat's forms, message rendering, router and stream subscriptions real.
const dispatch = vi.hoisted(() => vi.fn());
vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => dispatch,
}));
vi.mock('flavours/glitch/components/dropdown_menu', async () => {
  const { Link } =
    await vi.importActual<typeof ReactRouterDom>('react-router-dom');
  return {
    Dropdown: ({ items }: { items: MenuItem[] }) => (
      <div>
        {items.map((item) => {
          if (!item) return null;
          if ('to' in item)
            return (
              <Link key={item.text} to={item.to}>
                {item.text}
              </Link>
            );
          if (!('action' in item)) return null;
          const handleClick = item.action as () => void;
          return (
            <button
              key={item.text}
              type='button'
              data-dangerous={item.dangerous ? 'true' : undefined}
              onClick={handleClick}
            >
              {item.text}
            </button>
          );
        })}
      </div>
    ),
  };
});
vi.mock('flavours/glitch/components/avatar', () => ({
  Avatar: () => <div className='account__avatar' />,
}));
vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: ({ title, extraButton, children }: ColumnHeaderProps) => (
    <header>
      {title}
      {extraButton}
      {children}
    </header>
  ),
}));
vi.mock(
  'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container',
  () => ({
    default: function EmojiPicker({
      onPickEmoji,
    }: {
      onPickEmoji: (emoji: { native: string }) => void;
    }) {
      const handlePick = useCallback(() => {
        onPickEmoji({ native: '🎉' });
      }, [onPickEmoji]);
      return (
        <button type='button' onClick={handlePick}>
          Add reaction
        </button>
      );
    },
  }),
);
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const account = { id: 'me', acct: 'alice', display_name: 'Alice' };
const remote = { id: 'remote', acct: 'bob@remote.test', display_name: 'Bob' };
const attachment = {
  id: 'media-A',
  url: '/private-A',
  preview_url: '/preview-A',
  type: 'image',
  description: 'Private attachment A',
};
const message = (room = 'A') => ({
  id: `message-${room}`,
  conversation_id: room,
  content: `Private message ${room}`,
  created_at: '2026-11-02T00:00:00Z',
  edited_at: null,
  deleted_at: null,
  reply_to_id: null,
  account,
  reactions: [],
  media_attachments: [],
});
const conversation = (id: string) => ({
  id,
  type: 'direct',
  title: `Room ${id}`,
  description: null,
  unread: false,
  muted: false,
  archived: false,
  current_role: 'member',
  accounts: [account, remote],
  last_message: null,
});
const reaction = {
  message_id: 'message-A',
  reaction: '🎉',
  account: remote,
  created_at: '2026-11-02T00:01:00Z',
};
const settings = {
  policy: 'everyone',
  allow_group_invites: true,
  notifications: true,
  max_group_members: 10,
  max_attachments: 4,
  federation_enabled: true,
};
const deferred = <T,>() => {
  let complete!: (value: T) => void;
  const promise = new Promise<T>((resolve) => {
    complete = resolve;
  });
  return { promise, resolve: complete };
};
const mountChat = (path = '/chat/A') => {
  const history = createMemoryHistory({ initialEntries: [path] });
  const view = render(
    <IntlProvider locale='en'>
      <IdentityContext.Provider
        value={{
          signedIn: true,
          permissions: 0,
          accountId: 'me',
          disabledAccountId: undefined,
        }}
      >
        <Router history={history}>
          <Route path='/chat/:conversationId?/:view?'>
            <Chat />
          </Route>
        </Router>
      </IdentityContext.Provider>
    </IntlProvider>,
  );
  return { ...view, history };
};
const lastConfirmation = () => {
  const action = dispatch.mock.lastCall?.[0] as
    | {
        payload: {
          modalType: string;
          modalProps: { message: string; onConfirm: () => void };
        };
      }
    | undefined;
  expect(action?.payload.modalType).toBe('CONFIRM');
  return action?.payload.modalProps;
};
const confirmModal = async () => {
  await act(async () => {
    lastConfirmation()?.onConfirm();
    await Promise.resolve();
  });
};
const navigate = (
  history: ReturnType<typeof createMemoryHistory>,
  path: string,
) => {
  act(() => {
    history.push(path);
  });
};
const upload = (container: HTMLElement) => {
  const input = container.querySelector('input[type="file"]');
  if (!input) throw new Error('Missing attachment input');
  fireEvent.change(input, {
    target: { files: [new File(['private'], 'A.png', { type: 'image/png' })] },
  });
};
const composer = () =>
  screen.getByPlaceholderText<HTMLTextAreaElement>('Write a message');

const getResponse = (url: string): Promise<{ data: unknown }> => {
  if (url === '/api/v1/chat/conversations')
    return Promise.resolve({ data: [conversation('A'), conversation('B')] });
  if (/^\/api\/v1\/chat\/conversations\/[^/]+$/.test(url))
    return Promise.resolve({
      data: conversation(url.split('/').at(-1) ?? 'A'),
    });
  if (url === '/api/v1/chat/invitations') return Promise.resolve({ data: [] });
  if (url === '/api/v1/chat/settings')
    return Promise.resolve({ data: settings });
  if (url.endsWith('/messages'))
    return Promise.resolve({
      data: [message(url.includes('/A/') ? 'A' : 'B')],
    });
  throw new Error(`Unexpected GET ${url}`);
};
beforeEach(() => {
  vi.resetAllMocks();
  api.get.mockImplementation(getResponse);
  api.post.mockResolvedValue({ data: attachment });
  api.delete.mockResolvedValue({ data: {} });
});
afterEach(cleanup);

describe('Chat owner member removal', () => {
  let room = { ...conversation('A'), type: 'group', current_role: 'owner' };
  const membersPage = '/chat/A/members';

  beforeEach(() => {
    dispatch.mockClear();
    room = { ...conversation('A'), type: 'group', current_role: 'owner' };
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({ data: [room] });
      if (url === '/api/v1/chat/conversations/A')
        return Promise.resolve({ data: room });
      return getResponse(url);
    });
  });

  afterEach(() => vi.restoreAllMocks());

  it('does not show removal anywhere in the conversation', async () => {
    mountChat();
    await screen.findByText('Private message A');

    expect(
      screen.queryByRole('button', { name: /Remove .* from group/ }),
    ).toBeNull();
  });

  it('confirms removing another member and updates the roster after success', async () => {
    api.delete.mockResolvedValue({ data: { ...room, accounts: [account] } });
    mountChat(membersPage);
    const button = await screen.findByRole('button', {
      name: 'Remove Bob from group',
    });
    expect(button.getAttribute('data-dangerous')).toBe('true');
    expect(
      screen.queryByRole('button', { name: 'Remove Alice from group' }),
    ).toBeNull();

    fireEvent.click(button);

    expect(lastConfirmation()?.message).toBe(
      'Remove Bob from this group? They will need another invitation to rejoin.',
    );
    expect(api.delete).not.toHaveBeenCalled();
    await confirmModal();
    await waitFor(() => {
      expect(api.delete).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/A/members/remote',
      );
    });
    await screen.findByText('Members (1)');
    expect(
      screen.queryByRole('button', { name: 'Remove Bob from group' }),
    ).toBeNull();
  });

  it('does not remove the member until the removal is confirmed', async () => {
    mountChat(membersPage);
    fireEvent.click(
      await screen.findByRole('button', { name: 'Remove Bob from group' }),
    );

    expect(api.delete).not.toHaveBeenCalled();
    expect(screen.getByText('Members (2)')).toBeTruthy();
  });

  it('retains the member and reports a failed removal', async () => {
    api.delete.mockRejectedValue(new Error('Forbidden'));
    mountChat(membersPage);
    fireEvent.click(
      await screen.findByRole('button', { name: 'Remove Bob from group' }),
    );
    await confirmModal();

    await screen.findByText('The chat request could not be completed.');
    expect(screen.getByText('Members (2)')).toBeTruthy();
    expect(
      screen.getByRole('button', { name: 'Remove Bob from group' }),
    ).toBeTruthy();
  });

  it('shows other members the roster without removal', async () => {
    room.current_role = 'member';
    mountChat(membersPage);
    await screen.findByText('Members (2)');
    await screen.findByText('Bob');

    expect(
      screen.queryByRole('button', { name: /Remove .* from group/ }),
    ).toBeNull();
    expect(screen.queryByPlaceholderText('Search for an account')).toBeNull();
  });

  it('has no members screen for direct chats', async () => {
    room.type = 'direct';
    mountChat(membersPage);
    await screen.findByText('Private message A');

    expect(
      screen.queryByRole('button', { name: /Remove .* from group/ }),
    ).toBeNull();
  });

  it('allows the owner to remove a member while the group is archived', async () => {
    room.archived = true;
    api.delete.mockResolvedValue({ data: { ...room, accounts: [account] } });
    mountChat(membersPage);
    fireEvent.click(
      await screen.findByRole('button', { name: 'Remove Bob from group' }),
    );
    await confirmModal();

    await waitFor(() => {
      expect(api.delete).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/A/members/remote',
      );
    });
  });
});

describe('Chat conversation isolation', () => {
  it.each(['edit', 'reply', 'draft'])(
    'clears %s state and media when navigating A → home → B',
    async (mode) => {
      const { history, container } = mountChat();
      await screen.findByText('Private message A');
      if (mode !== 'draft')
        fireEvent.click(
          screen.getByRole('button', {
            name: mode === 'edit' ? 'Edit' : 'Reply',
          }),
        );
      fireEvent.change(composer(), { target: { value: 'Private draft A' } });
      upload(container);
      await screen.findByAltText('Private attachment A');

      navigate(history, '/chat');
      await screen.findByRole('button', { name: /Room B/ });
      fireEvent.click(screen.getByRole('button', { name: /Room B/ }));
      await screen.findByText('Private message B');

      expect(composer().value).toBe('');
      expect(screen.queryByText('Private message A')).toBeNull();
      expect(screen.queryByAltText('Private attachment A')).toBeNull();
      expect(screen.queryByText('Editing message')).toBeNull();
      expect(screen.queryByText(/Replying to/)).toBeNull();
      fireEvent.change(composer(), { target: { value: 'Hello B' } });
      api.post.mockResolvedValueOnce({
        data: { ...message('B'), id: 'sent-B', content: 'Hello B' },
      });
      fireEvent.click(screen.getByRole('button', { name: 'Send' }));
      await screen.findByText('Hello B');
      expect(api.post).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/B/messages',
        { text: 'Hello B', reply_to_id: null, media_ids: [] },
      );
      expect(api.patch).not.toHaveBeenCalled();
    },
  );

  it('does not display A messages while B is loading or after a stale A response', async () => {
    const pendingA = deferred<{ data: ReturnType<typeof message>[] }>();
    const pendingB = deferred<{ data: ReturnType<typeof message>[] }>();
    api.get.mockImplementation((url: string) => {
      if (url.includes('/A/messages')) return pendingA.promise;
      if (url.includes('/B/messages')) return pendingB.promise;
      return getResponse(url);
    });
    const { history } = mountChat();
    await screen.findByText('Room A');
    act(() => {
      emitChatStreamEvent({ event: 'chat.message', payload: message('A') });
    });
    expect(screen.getByText('Private message A')).toBeTruthy();
    navigate(history, '/chat/B');
    expect.soft(screen.queryByText('Private message A')).toBeNull();
    await act(async () => {
      pendingB.resolve({ data: [message('B')] });
      await pendingB.promise;
    });
    await act(async () => {
      pendingA.resolve({ data: [message('A')] });
      await pendingA.promise;
    });
    expect(screen.getByText('Private message B')).toBeTruthy();
    expect(screen.queryByText('Private message A')).toBeNull();
  });

  it.each([
    ['send', 'B'],
    ['upload', 'B'],
    ['send', 'A'],
    ['upload', 'A'],
  ])(
    'ignores delayed %s completion after A → home → %s',
    async (operation, destination) => {
      const pending = deferred<{
        data: ReturnType<typeof message> | typeof attachment;
      }>();
      const { history, container } = mountChat();
      await screen.findByText('Private message A');
      api.post.mockImplementation((url: string) =>
        url.endsWith('/read') ? Promise.resolve({}) : pending.promise,
      );
      fireEvent.change(composer(), { target: { value: 'Old A draft' } });
      if (operation === 'send')
        fireEvent.click(screen.getByRole('button', { name: 'Send' }));
      else upload(container);
      navigate(history, '/chat');
      navigate(history, `/chat/${destination}`);
      await screen.findByText(`Private message ${destination}`);
      fireEvent.change(composer(), { target: { value: 'New draft' } });
      expect
        .soft(
          screen.getByRole<HTMLButtonElement>('button', { name: 'Send' })
            .disabled,
        )
        .toBe(false);
      await act(async () => {
        pending.resolve({
          data:
            operation === 'send'
              ? { ...message(), id: 'sent-old', content: 'Old sent A' }
              : attachment,
        });
        await pending.promise;
      });
      expect.soft(composer().value).toBe('New draft');
      expect.soft(screen.queryByText('Old sent A')).toBeNull();
      expect(screen.queryByAltText('Private attachment A')).toBeNull();
    },
  );
});

describe('Chat pagination', () => {
  it('loads the selected conversation even when it is outside the first list page', async () => {
    mountChat('/chat/C');
    expect(await screen.findByText('Room C')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Mute' })).toBeTruthy();
  });

  it('loads older messages without removing the current messages', async () => {
    const recent = Array.from({ length: 40 }, (_, index) => ({
      ...message(),
      id: String(index + 10),
      content: `Recent ${index}`,
    }));
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/A/messages')) {
          return Promise.resolve({
            data:
              options?.params?.max_id === '10'
                ? [{ ...message(), id: '9', content: 'Older message' }]
                : recent,
          });
        }
        return getResponse(url);
      },
    );
    mountChat();
    await screen.findByText('Recent 39');
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    expect(await screen.findByText('Older message')).toBeTruthy();
    expect(screen.getByText('Recent 39')).toBeTruthy();
  });

  it.each(['chat.message_update', 'chat.reaction'])(
    'preserves %s received while an older message page is loading',
    async (event) => {
      const older = { ...message(), id: '9', content: 'Old content' };
      const pending = deferred<{ data: (typeof older)[] }>();
      const recent = Array.from({ length: 40 }, (_, index) => ({
        ...message(),
        id: String(index + 10),
        content: `Recent ${index}`,
      }));
      api.get.mockImplementation(
        (url: string, options?: { params?: { max_id?: string } }) => {
          if (url.endsWith('/A/messages'))
            return options?.params?.max_id
              ? pending.promise
              : Promise.resolve({ data: recent });
          return getResponse(url);
        },
      );
      mountChat();
      await screen.findByText('Recent 39');
      fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
      act(() => {
        emitChatStreamEvent({
          event,
          payload:
            event === 'chat.reaction'
              ? { ...reaction, message_id: '9' }
              : { ...older, content: 'Edited history' },
        });
      });
      await act(async () => {
        pending.resolve({ data: [older] });
        await pending.promise;
      });
      if (event === 'chat.reaction')
        expect(screen.getByRole('button', { name: '🎉' })).toBeTruthy();
      else expect(screen.getByText('Edited history')).toBeTruthy();
    },
  );

  it('loads conversations beyond the first page', async () => {
    const firstPage = Array.from({ length: 20 }, (_, index) =>
      conversation(String(30 - index)),
    );
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url === '/api/v1/chat/conversations') {
          return Promise.resolve({
            data:
              options?.params?.max_id === '11'
                ? [conversation('10')]
                : firstPage,
          });
        }
        return getResponse(url);
      },
    );
    mountChat('/chat');
    await screen.findByText('Room 30');
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    expect(await screen.findByText('Room 10')).toBeTruthy();
    expect(screen.getByText('Room 30')).toBeTruthy();
    await act(async () => {
      emitChatStreamEvent({ event: 'chat.message', payload: message() });
      await Promise.resolve();
    });
    expect(screen.getByText('Room 10')).toBeTruthy();
  });
});

describe('Chat live updates', () => {
  it.each(['chat.message', 'chat.message_update', 'chat.reaction'])(
    'preserves %s received while the initial message snapshot is pending',
    async (event) => {
      const pending = deferred<{ data: ReturnType<typeof message>[] }>();
      api.get.mockImplementation((url: string) =>
        url.includes('/A/messages') ? pending.promise : getResponse(url),
      );
      mountChat();
      await screen.findByText('Room A');
      act(() => {
        emitChatStreamEvent({
          event,
          payload:
            event === 'chat.reaction'
              ? reaction
              : {
                  ...message(),
                  id: event === 'chat.message' ? 'new-A' : 'message-A',
                  content: 'Live content',
                },
        });
      });
      await act(async () => {
        pending.resolve({ data: [message()] });
        await pending.promise;
      });
      if (event === 'chat.reaction') {
        expect(screen.getByRole('button', { name: '🎉' })).toBeTruthy();
      } else {
        expect(screen.getByText('Live content')).toBeTruthy();
        if (event === 'chat.message')
          expect(screen.getByText('Private message A')).toBeTruthy();
        else expect(screen.queryByText('Private message A')).toBeNull();
      }
    },
  );

  it('removes private attachments and reactions when a message is deleted', async () => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({
            data: [
              {
                ...message(),
                media_attachments: [attachment],
                reactions: [reaction],
              },
            ],
          })
        : getResponse(url),
    );
    mountChat();
    await screen.findByAltText('Private attachment A');
    expect(screen.getByRole('button', { name: '🎉' })).toBeTruthy();
    act(() => {
      emitChatStreamEvent({
        event: 'chat.message_delete',
        payload: { id: 'message-A', conversation_id: 'A' },
      });
    });
    expect(screen.getByText('This message was deleted.')).toBeTruthy();
    expect(screen.queryByText('Private message A')).toBeNull();
    expect(screen.queryByAltText('Private attachment A')).toBeNull();
    expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
    act(() => {
      emitChatStreamEvent({ event: 'chat.reaction', payload: reaction });
    });
    expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
  });

  it.each(['initial', 'reload'])(
    'retains a deletion received before the %s GET completes',
    async (request) => {
      const snapshot = {
        ...message(),
        media_attachments: [attachment],
        reactions: [reaction],
      };
      const pending = deferred<{ data: (typeof snapshot)[] }>();
      if (request === 'initial') {
        api.get.mockImplementation((url: string) =>
          url.includes('/A/messages') ? pending.promise : getResponse(url),
        );
      }
      mountChat();
      await screen.findByText('Room A');
      if (request === 'reload') {
        await screen.findByText('Private message A');
        api.get.mockImplementation((url: string) =>
          url.includes('/A/messages') ? pending.promise : getResponse(url),
        );
        act(() => {
          emitChatStreamEvent({
            event: 'chat.conversation_update',
            payload: { conversation_id: 'A' },
          });
        });
      }
      act(() => {
        emitChatStreamEvent({
          event: 'chat.message_delete',
          payload: { id: 'message-A', conversation_id: 'A' },
        });
      });
      await act(async () => {
        pending.resolve({ data: [snapshot] });
        await pending.promise;
      });
      expect(screen.queryByText('Private message A')).toBeNull();
      expect(screen.queryByAltText('Private attachment A')).toBeNull();
      expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
      expect(screen.getByText('This message was deleted.')).toBeTruthy();
    },
  );

  it.each(['send', 'edit'])(
    'retains a deletion received before the %s response completes',
    async (operation) => {
      const id = operation === 'edit' ? 'message-A' : 'sent-A';
      const snapshot = {
        ...message(),
        id,
        content: 'Delayed content',
        media_attachments: [attachment],
        reactions: [reaction],
      };
      const pending = deferred<{ data: typeof snapshot }>();
      mountChat();
      await screen.findByText('Private message A');
      if (operation === 'edit') {
        fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
        api.patch.mockReturnValueOnce(pending.promise);
      } else {
        api.post.mockReturnValueOnce(pending.promise);
      }
      fireEvent.change(composer(), { target: { value: 'Delayed content' } });
      fireEvent.click(screen.getByRole('button', { name: 'Send' }));
      act(() => {
        emitChatStreamEvent({
          event: 'chat.message_delete',
          payload: { id, conversation_id: 'A' },
        });
      });
      await act(async () => {
        pending.resolve({ data: snapshot });
        await pending.promise;
      });
      expect(screen.queryByText('Delayed content')).toBeNull();
      expect(screen.queryByAltText('Private attachment A')).toBeNull();
      expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
      expect(screen.getByText('This message was deleted.')).toBeTruthy();
    },
  );

  it.each(['chat.message', 'chat.message_update'])(
    'retains a deletion before a stale %s stream snapshot',
    async (event) => {
      if (event === 'chat.message') {
        api.get.mockImplementation((url: string) =>
          url.includes('/A/messages')
            ? Promise.resolve({ data: [] })
            : getResponse(url),
        );
      }
      mountChat();
      await screen.findByText('Room A');
      if (event === 'chat.message_update')
        await screen.findByText('Private message A');
      act(() => {
        emitChatStreamEvent({
          event: 'chat.message_delete',
          payload: { id: 'message-A', conversation_id: 'A' },
        });
        emitChatStreamEvent({
          event,
          payload: {
            ...message(),
            media_attachments: [attachment],
            reactions: [reaction],
          },
        });
      });
      expect(screen.queryByText('Private message A')).toBeNull();
      expect(screen.queryByAltText('Private attachment A')).toBeNull();
      expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
      expect(screen.getByText('This message was deleted.')).toBeTruthy();
    },
  );

  it('retains a server tombstone when a stale stream update arrives', async () => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({
            data: [
              {
                ...message(),
                content: null,
                deleted_at: '2026-11-02T00:02:00Z',
              },
            ],
          })
        : getResponse(url),
    );
    mountChat();
    await screen.findByText('This message was deleted.');
    act(() => {
      emitChatStreamEvent({
        event: 'chat.message_update',
        payload: {
          ...message(),
          media_attachments: [attachment],
          reactions: [reaction],
        },
      });
    });
    expect(screen.queryByText('Private message A')).toBeNull();
    expect(screen.queryByAltText('Private attachment A')).toBeNull();
    expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
    expect(screen.getByText('This message was deleted.')).toBeTruthy();
  });

  it('does not offer a reaction picker on your own message', async () => {
    mountChat();
    await screen.findByText('Private message A');

    expect(screen.queryByRole('button', { name: 'Add reaction' })).toBeNull();
    expect(screen.getByRole('button', { name: 'Edit' })).toBeTruthy();
  });

  it('does not restore a reaction when its local request finishes after deletion', async () => {
    const pending = deferred<{ data: typeof reaction }>();
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations/A/messages'
        ? Promise.resolve({ data: [{ ...message(), account: remote }] })
        : getResponse(url),
    );
    mountChat();
    await screen.findByText('Private message A');
    api.post.mockReturnValueOnce(pending.promise);
    fireEvent.click(screen.getByRole('button', { name: 'Add reaction' }));
    act(() => {
      emitChatStreamEvent({
        event: 'chat.message_delete',
        payload: { id: 'message-A', conversation_id: 'A' },
      });
    });
    await act(async () => {
      pending.resolve({ data: { ...reaction, account } });
      await pending.promise;
    });
    expect(screen.getByText('This message was deleted.')).toBeTruthy();
    expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
  });

  it('updates the invitation count and list on an incoming invitation after navigation', async () => {
    const { history } = mountChat();
    await screen.findByText('Private message A');
    navigate(history, '/chat/B');
    await screen.findByText('Private message B');
    navigate(history, '/chat');
    fireEvent.click(await screen.findByRole('button', { name: 'Invitations' }));
    await screen.findByText('You have no chat invitations.');
    const invitation = {
      id: 'invite-C',
      conversation: conversation('C'),
      inviter: remote,
    };
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/invitations'
        ? Promise.resolve({ data: [invitation] })
        : getResponse(url),
    );
    act(() => {
      emitChatStreamEvent({ event: 'chat.invitation', payload: invitation });
    });
    await screen.findByText('Room C');
    expect(
      screen.getByRole('button', { name: /Invitations\s*1/ }),
    ).toBeTruthy();
  });

  it('renders account-bearing remote reactions once and safely ignores malformed reactions', async () => {
    mountChat();
    await screen.findByText('Private message A');
    act(() => {
      emitChatStreamEvent({ event: 'chat.reaction', payload: reaction });
      emitChatStreamEvent({ event: 'chat.reaction', payload: reaction });
    });
    expect(screen.getAllByRole('button', { name: '🎉' })).toHaveLength(1);
    expect(screen.getByRole('button', { name: '🎉' }).title).toBe(
      'bob@remote.test',
    );
    act(() => {
      emitChatStreamEvent({
        event: 'chat.reaction',
        payload: {
          message_id: 'message-A',
          reaction: '💥',
          account_id: 'unknown',
        },
      });
    });
    expect(screen.queryByRole('button', { name: '💥' })).toBeNull();
    act(() => {
      emitChatStreamEvent({
        event: 'chat.reaction_delete',
        payload: {
          message_id: 'message-A',
          account_id: 'remote',
          reaction: '🎉',
        },
      });
    });
    expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
  });
});

describe('Chat live updates', () => {
  it('marks a message from someone else read when it arrives in the open room', async () => {
    mountChat();
    await screen.findByText('Private message A');
    api.post.mockClear();

    await act(async () => {
      emitChatStreamEvent({
        event: 'chat.message',
        payload: { ...message('A'), id: 'incoming', account: remote },
      });
      await Promise.resolve();
    });

    expect(api.post).toHaveBeenCalledWith('/api/v1/chat/conversations/A/read', {
      message_id: 'incoming',
    });
  });

  it('does not mark the sender own message read again', async () => {
    mountChat();
    await screen.findByText('Private message A');
    api.post.mockClear();

    act(() => {
      emitChatStreamEvent({
        event: 'chat.message',
        payload: { ...message('A'), id: 'own' },
      });
    });

    expect(api.post).not.toHaveBeenCalled();
  });

  it('leaves a room that was deleted while it was open', async () => {
    const { history } = mountChat();
    await screen.findByText('Private message A');

    act(() => {
      emitChatStreamEvent({
        event: 'chat.conversation_delete',
        payload: { conversation_id: 'A' },
      });
    });

    expect(history.location.pathname).toBe('/chat');
  });
});

describe('Chat review additions', () => {
  it('applies a local tombstone after deleting a message', async () => {
    mountChat();
    await screen.findByText('Private message A');

    fireEvent.click(screen.getByRole('button', { name: 'Delete' }));

    await waitFor(() => {
      expect(screen.getByText('This message was deleted.')).toBeTruthy();
    });
    expect(api.delete).toHaveBeenCalledWith('/api/v1/chat/messages/message-A');
  });

  it('clears an attachment caption while keeping the existing image', async () => {
    const original = { ...message(), media_attachments: [attachment] };
    api.get.mockImplementation((url: string) =>
      url.endsWith('/messages')
        ? Promise.resolve({ data: [original] })
        : getResponse(url),
    );
    api.patch.mockResolvedValue({
      data: { ...original, content: '', edited_at: '2026-11-03T00:00:00Z' },
    });

    mountChat();
    await screen.findByAltText('Private attachment A');
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    fireEvent.change(composer(), { target: { value: '' } });

    const send = screen.getByRole<HTMLButtonElement>('button', {
      name: 'Send',
    });
    expect(send.disabled).toBe(false);
    fireEvent.click(send);

    await waitFor(() => {
      expect(screen.queryByText('Editing message')).toBeNull();
    });
    expect(api.patch).toHaveBeenCalledWith('/api/v1/chat/messages/message-A', {
      text: '',
    });
    expect(screen.queryByText('Private message A')).toBeNull();
    expect(screen.getByAltText('Private attachment A')).toBeTruthy();
    expect(send.disabled).toBe(true);
  });

  it('keeps empty text-only edits disabled', async () => {
    mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    fireEvent.change(composer(), { target: { value: '   ' } });

    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Send' }).disabled,
    ).toBe(true);
    const form = composer().closest('form');
    if (!form) throw new Error('Missing composer form');
    fireEvent.submit(form);
    expect(api.patch).not.toHaveBeenCalled();
  });

  it('renders local custom emoji reactions as images', async () => {
    mountChat();
    await screen.findByText('Private message A');

    act(() => {
      emitChatStreamEvent({
        event: 'chat.reaction',
        payload: {
          ...reaction,
          reaction: ':blobcat:',
          url: '/emoji/blobcat.png',
          static_url: '/emoji/blobcat.png',
        },
      });
    });

    const button = screen.getByRole('button', { name: ':blobcat:' });
    expect(within(button).getByRole('img', { name: ':blobcat:' })).toBeTruthy();
  });

  it('polls processing media until it is ready', async () => {
    const pendingMedia = {
      id: 'media-processing',
      url: null as string | null,
      preview_url: null as string | null,
      type: 'video',
      description: null,
    };
    const readyMedia = {
      ...pendingMedia,
      url: '/media-ready.mp4',
      preview_url: '/media-ready.png',
    };
    api.post.mockImplementation((url: string) => {
      if (url === '/api/v2/media')
        return Promise.resolve({ data: pendingMedia });
      return Promise.resolve({ data: attachment });
    });
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/media/media-processing')
        return Promise.resolve({ data: readyMedia });
      return getResponse(url);
    });

    const { container } = mountChat();
    await screen.findByText('Private message A');
    upload(container);

    await waitFor(() => {
      expect(container.querySelector('video')?.getAttribute('src')).toBe(
        '/media-ready.mp4',
      );
    });
  });

  it('does not expose message actions in an archived room', async () => {
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({
          data: [{ ...conversation('A'), archived: true }],
        });
      if (url.endsWith('/messages'))
        return Promise.resolve({ data: [message('A')] });
      if (url === '/api/v1/chat/invitations')
        return Promise.resolve({ data: [] });
      if (url === '/api/v1/chat/settings')
        return Promise.resolve({ data: settings });
      return getResponse(url);
    });

    mountChat();
    await screen.findByText('Private message A');

    expect(screen.queryByRole('button', { name: 'Reply' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Edit' })).toBeNull();
    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Send' }).disabled,
    ).toBe(true);
  });
});

describe('Chat screen lifecycle', () => {
  const groupRoom = {
    ...conversation('A'),
    type: 'group',
    current_role: 'member',
  };
  const roomResponse = (room: typeof groupRoom) => (url: string) => {
    if (url === '/api/v1/chat/conversations')
      return Promise.resolve({ data: [room] });
    if (url === '/api/v1/chat/conversations/A')
      return Promise.resolve({ data: room });
    return getResponse(url);
  };
  const setVisibility = (state: DocumentVisibilityState) => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value: state,
    });
  };

  afterEach(() => {
    setVisibility('visible');
    vi.restoreAllMocks();
  });

  it('does not pull the user back when leaving finishes after they moved on', async () => {
    api.get.mockImplementation(roomResponse(groupRoom));
    const leaving = deferred<{ data: unknown }>();
    api.delete.mockReturnValue(leaving.promise);

    const { history, unmount } = mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Leave group' }));
    await confirmModal();
    unmount();
    history.push('/home');

    await act(async () => {
      leaving.resolve({ data: {} });
      await Promise.resolve();
    });

    expect(history.location.pathname).toBe('/home');
  });

  it('shows an error when leaving fails', async () => {
    api.get.mockImplementation(roomResponse(groupRoom));
    api.delete.mockRejectedValue(new Error('rate limited'));

    const { history } = mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Leave group' }));
    await confirmModal();

    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(history.location.pathname).toBe('/chat/A');
  });

  it('asks before deleting a group for everyone', async () => {
    const room = { ...groupRoom, current_role: 'owner' };
    api.get.mockImplementation(roomResponse(room));
    api.delete.mockResolvedValue({ data: {} });

    mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Delete group' }));

    expect(lastConfirmation()?.message).toContain('Delete this group');
    expect(api.delete).not.toHaveBeenCalled();

    await confirmModal();
    expect(api.delete).toHaveBeenCalledWith('/api/v1/chat/conversations/A');
  });

  it('keeps the edit open and reports the failure when saving an edit fails', async () => {
    api.patch.mockRejectedValue(new Error('offline'));

    mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    fireEvent.change(composer(), { target: { value: 'Edited text' } });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));

    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(screen.getByText('Editing message')).toBeTruthy();
    expect(composer().value).toBe('Edited text');
  });

  it('clears an old error when the next action starts', async () => {
    api.patch.mockRejectedValueOnce(new Error('offline'));
    api.patch.mockResolvedValue({
      data: { ...message(), content: 'Edited text' },
    });

    mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    fireEvent.change(composer(), { target: { value: 'Edited text' } });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    await screen.findByRole('alert');

    fireEvent.click(screen.getByRole('button', { name: 'Send' }));

    await waitFor(() => {
      expect(screen.queryByRole('alert')).toBeNull();
    });
  });

  it('restores the unsent draft after cancelling an edit', async () => {
    mountChat();
    await screen.findByText('Private message A');
    fireEvent.change(composer(), { target: { value: 'My draft' } });

    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    expect(composer().value).toBe('Private message A');

    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(composer().value).toBe('My draft');
  });

  it('keeps typed text when cancelling a reply', async () => {
    mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Reply' }));
    fireEvent.change(composer(), { target: { value: 'My reply' } });

    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(screen.queryByText(/Replying to/)).toBeNull();
    expect(composer().value).toBe('My reply');
  });

  it('leaves edit mode when the room is archived, without the stale edit returning later', async () => {
    const live = { ...conversation('A') };
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({ data: [{ ...live }] });
      return getResponse(url);
    });

    mountChat();
    await screen.findByText('Private message A');
    fireEvent.change(composer(), { target: { value: 'My draft' } });
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    expect(screen.getByText('Editing message')).toBeTruthy();

    live.archived = true;
    act(() => {
      emitChatStreamEvent({
        event: 'chat.conversation_update',
        payload: { id: 'A' },
      });
    });
    await screen.findByText('This group is archived.');

    await waitFor(() => {
      expect(screen.queryByText('Editing message')).toBeNull();
    });
    expect(composer().disabled).toBe(true);
    expect(composer().value).toBe('My draft');

    live.archived = false;
    act(() => {
      emitChatStreamEvent({
        event: 'chat.conversation_update',
        payload: { id: 'A' },
      });
    });
    await waitFor(() => {
      expect(composer().disabled).toBe(false);
    });
    expect(screen.queryByText('Editing message')).toBeNull();
    expect(composer().value).toBe('My draft');
  });

  it('leaves edit mode when the message being edited is deleted elsewhere', async () => {
    mountChat();
    await screen.findByText('Private message A');
    fireEvent.change(composer(), { target: { value: 'My draft' } });
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));

    act(() => {
      emitChatStreamEvent({
        event: 'chat.message_delete',
        payload: { id: 'message-A', conversation_id: 'A' },
      });
    });

    await waitFor(() => {
      expect(screen.queryByText('Editing message')).toBeNull();
    });
    expect(composer().value).toBe('My draft');
  });

  it('shows new room details after a saved edit instead of the old form values', async () => {
    const live = { ...groupRoom, current_role: 'owner', title: 'Old name' };
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({ data: [{ ...live }] });
      return getResponse(url);
    });
    api.patch.mockImplementation(() => {
      live.title = 'Saved name';
      return Promise.resolve({ data: { ...live } });
    });

    mountChat();
    fireEvent.click(
      await screen.findByRole('link', { name: 'Group settings' }),
    );
    const title =
      await screen.findByPlaceholderText<HTMLInputElement>('Group name');
    await waitFor(() => {
      expect(title.value).toBe('Old name');
    });
    fireEvent.change(title, { target: { value: 'Saved name' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save group details' }));
    await waitFor(() => {
      expect(api.patch).toHaveBeenCalled();
    });

    live.title = 'Renamed elsewhere';
    act(() => {
      emitChatStreamEvent({
        event: 'chat.conversation_update',
        payload: { id: 'A' },
      });
    });

    await waitFor(() => {
      expect(title.value).toBe('Renamed elsewhere');
    });
  });

  it('does not repeat a reaction the user already made', async () => {
    const received = {
      ...message(),
      account: remote,
      reactions: [{ ...reaction, account }],
    };
    api.get.mockImplementation((url: string) =>
      url.endsWith('/messages')
        ? Promise.resolve({ data: [received] })
        : getResponse(url),
    );

    mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Add reaction' }));

    expect(api.post).not.toHaveBeenCalledWith(
      '/api/v1/chat/messages/message-A/reactions',
      expect.anything(),
    );
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('does not mark a message as read while the tab is in the background', async () => {
    mountChat();
    await screen.findByText('Private message A');
    api.post.mockClear();
    setVisibility('hidden');

    act(() => {
      emitChatStreamEvent({
        event: 'chat.message',
        payload: {
          ...message(),
          id: 'message-new',
          content: 'Arrived in background',
          account: remote,
        },
      });
    });
    await screen.findByText('Arrived in background');

    expect(api.post).not.toHaveBeenCalledWith(
      '/api/v1/chat/conversations/A/read',
      expect.anything(),
    );
  });

  it('marks the room as read when the user comes back to the tab', async () => {
    const unreadRoom = { ...conversation('A'), unread: true };
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations'
        ? Promise.resolve({ data: [unreadRoom] })
        : getResponse(url),
    );
    setVisibility('hidden');

    mountChat();
    await screen.findByText('Private message A');
    expect(api.post).not.toHaveBeenCalledWith(
      '/api/v1/chat/conversations/A/read',
    );

    setVisibility('visible');
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });

    await waitFor(() => {
      expect(api.post).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/A/read',
      );
    });
  });

  it('ignores a conversation list response that arrives out of order', async () => {
    const older = deferred<{ data: unknown }>();
    let requests = 0;
    api.get.mockImplementation((url: string) => {
      if (url !== '/api/v1/chat/conversations') return getResponse(url);
      requests += 1;
      if (requests === 2) return older.promise;
      return Promise.resolve({
        data: [{ ...conversation('A'), title: `Version ${requests}` }],
      });
    });

    mountChat();
    await screen.findByText('Version 1');
    act(() => {
      emitChatStreamEvent({
        event: 'chat.conversation_update',
        payload: { id: 'A' },
      });
      emitChatStreamEvent({
        event: 'chat.conversation_update',
        payload: { id: 'A' },
      });
    });
    await screen.findByText('Version 3');

    await act(async () => {
      older.resolve({
        data: [{ ...conversation('A'), title: 'Old version' }],
      });
      await Promise.resolve();
    });

    expect(screen.queryByText('Old version')).toBeNull();
    expect(screen.getByText('Version 3')).toBeTruthy();
  });

  it('explains that a room is gone and keeps the composer away from it', async () => {
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({ data: [] });
      if (url === '/api/v1/chat/conversations/A')
        return Promise.reject(
          Object.assign(new Error('Not found'), {
            response: { status: 404 },
          }),
        );
      if (url.endsWith('/messages'))
        return Promise.reject(
          Object.assign(new Error('Not found'), {
            response: { status: 404 },
          }),
        );
      return getResponse(url);
    });

    mountChat();

    expect(await screen.findByRole('alert')).toBeTruthy();
    await waitFor(() => {
      expect(screen.queryByPlaceholderText('Write a message')).toBeNull();
    });
  });

  it('counts code points when limiting message length, like the server', async () => {
    mountChat();
    await screen.findByText('Private message A');

    fireEvent.change(composer(), { target: { value: '🍒'.repeat(4096) } });
    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Send' }).disabled,
    ).toBe(false);

    fireEvent.change(composer(), { target: { value: '🍒'.repeat(4097) } });
    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Send' }).disabled,
    ).toBe(true);
    expect(screen.getByText('This message is too long.')).toBeTruthy();
  });

  it('tells the user when too many files are selected', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/settings'
        ? Promise.resolve({ data: { ...settings, max_attachments: 0 } })
        : getResponse(url),
    );

    const { container } = mountChat();
    await screen.findByText('Private message A');
    upload(container);

    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(api.post).not.toHaveBeenCalledWith(
      '/api/v2/media',
      expect.anything(),
    );
  });

  it('says so when a search finds nothing', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/messages/search'
        ? Promise.resolve({ data: [] })
        : getResponse(url),
    );

    mountChat('/chat');
    fireEvent.click(
      await screen.findByRole('button', { name: 'Search messages' }),
    );
    const search = screen.getByPlaceholderText('Search messages');
    fireEvent.change(search, { target: { value: 'nothing' } });
    fireEvent.submit(search.closest('form') as HTMLFormElement);

    expect(await screen.findByText('No messages found.')).toBeTruthy();
  });

  it('calls rooms groups in every room tab', async () => {
    mountChat('/chat');

    expect(
      await screen.findByRole('button', { name: 'Joined groups' }),
    ).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Your groups' })).toBeTruthy();
  });

  it('labels the unread marker through translations', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations'
        ? Promise.resolve({
            data: [{ ...conversation('A'), unread: true }],
          })
        : getResponse(url),
    );

    const { container } = mountChat('/chat');
    await screen.findByText('Room A');

    expect(
      container
        .querySelector('.chat-native__conversations i')
        ?.getAttribute('aria-label'),
    ).toBe('Unread messages');
  });
});

describe('Chat room layout', () => {
  const room = (id = 'A', role = 'owner', type = 'group') => ({
    ...conversation(id),
    type,
    current_role: role,
  });
  const respondWith = (current: ReturnType<typeof room>) => {
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({ data: [current] });
      if (url === '/api/v1/chat/conversations/A')
        return Promise.resolve({ data: current });
      return getResponse(url);
    });
  };

  beforeEach(() => {
    dispatch.mockClear();
  });

  it('keeps only the conversation and composer on the room screen', async () => {
    respondWith(room());
    const { container } = mountChat();
    await screen.findByText('Private message A');

    expect(screen.queryByText('Bob')).toBeNull();
    expect(screen.queryByPlaceholderText('Group name')).toBeNull();
    expect(screen.queryByPlaceholderText('Search for an account')).toBeNull();
    expect(
      container
        .querySelector('.chat-native__composer')
        ?.previousElementSibling?.classList.contains('chat-native__messages'),
    ).toBe(true);
  });

  it('gives owners management in the header menu, marking deletion dangerous', async () => {
    respondWith(room());
    mountChat();
    await screen.findByText('Private message A');

    expect(screen.getByRole('button', { name: 'Mute' })).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Members (2)' })).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Group settings' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Archive' })).toBeTruthy();
    expect(
      screen
        .getByRole('button', { name: 'Delete group' })
        .getAttribute('data-dangerous'),
    ).toBe('true');
  });

  it('gives other members only what applies to them', async () => {
    respondWith(room('A', 'member'));
    mountChat();
    await screen.findByText('Private message A');

    expect(screen.getByRole('link', { name: 'Members (2)' })).toBeTruthy();
    expect(screen.queryByRole('link', { name: 'Group settings' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Archive' })).toBeNull();
    expect(
      screen
        .getByRole('button', { name: 'Leave group' })
        .getAttribute('data-dangerous'),
    ).toBe('true');
  });

  it('offers only muting in a direct chat', async () => {
    respondWith(room('A', 'member', 'direct'));
    mountChat();
    await screen.findByText('Private message A');

    expect(screen.getByRole('button', { name: 'Mute' })).toBeTruthy();
    expect(screen.queryByRole('link', { name: /Members/ })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Leave group' })).toBeNull();
  });

  it('opens group settings on their own screen and returns to the messages', async () => {
    respondWith(room());
    const { history } = mountChat();
    fireEvent.click(
      await screen.findByRole('link', { name: 'Group settings' }),
    );

    expect(history.location.pathname).toBe('/chat/A/settings');
    expect(await screen.findByPlaceholderText('Group name')).toBeTruthy();
    expect(screen.queryByText('Private message A')).toBeNull();
    expect(screen.queryByPlaceholderText('Write a message')).toBeNull();

    act(() => {
      history.goBack();
    });
    expect(await screen.findByText('Private message A')).toBeTruthy();
  });

  it('keeps inviting with the members, not in the conversation', async () => {
    respondWith(room());
    const { history } = mountChat();
    fireEvent.click(await screen.findByRole('link', { name: 'Members (2)' }));

    expect(history.location.pathname).toBe('/chat/A/members');
    expect(
      await screen.findByPlaceholderText('Search for an account'),
    ).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Invite' })).toBeTruthy();
    expect(screen.getByText('Bob')).toBeTruthy();
    expect(screen.getByText('@bob@remote.test')).toBeTruthy();
    expect(screen.queryByPlaceholderText('Write a message')).toBeNull();
  });

  it('does not open group settings for someone who is not the owner', async () => {
    respondWith(room('A', 'member'));
    mountChat('/chat/A/settings');
    await screen.findByText('Private message A');

    expect(screen.queryByPlaceholderText('Group name')).toBeNull();
  });
});

describe('Chat scrolling', () => {
  const scrollIntoView = vi.fn();
  // The window stands in for whichever element scrolls in the current layout.
  const scrollTo = (distanceFromBottom: number) => {
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
      bottom: window.innerHeight + distanceFromBottom,
    } as DOMRect);
    fireEvent.scroll(window);
  };
  const liveMessage = (from: typeof account) => {
    act(() => {
      emitChatStreamEvent({
        event: 'chat.message',
        payload: {
          ...message(),
          id: 'live',
          content: 'Live message',
          account: from,
        },
      });
    });
  };
  const openRoom = async () => {
    const view = mountChat();
    await screen.findByText('Private message A');
    await waitFor(() => {
      expect(scrollIntoView).toHaveBeenCalledTimes(1);
    });
    return view;
  };

  beforeEach(() => {
    scrollIntoView.mockClear();
    Element.prototype.scrollIntoView = scrollIntoView;
  });

  afterEach(() => {
    Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('opens a room at its newest message, clear of the composer', async () => {
    const { container } = await openRoom();

    const target = scrollIntoView.mock.instances[0] as Element;
    const composerForm = container.querySelector(
      '.chat-native__composer',
    ) as Element;
    expect(composerForm.compareDocumentPosition(target)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING,
    );
  });

  it('leaves someone reading older messages where they are', async () => {
    await openRoom();
    scrollTo(3000);
    scrollIntoView.mockClear();

    liveMessage(remote);
    await screen.findByText('Live message');

    expect(scrollIntoView).not.toHaveBeenCalled();
  });

  it('follows new messages when already at the bottom', async () => {
    await openRoom();
    scrollTo(100);
    scrollIntoView.mockClear();

    liveMessage(remote);
    await screen.findByText('Live message');

    expect(scrollIntoView).toHaveBeenCalledTimes(1);
  });

  it('shows my own new message even when scrolled up', async () => {
    await openRoom();
    scrollTo(3000);
    scrollIntoView.mockClear();

    liveMessage(account);
    await screen.findByText('Live message');

    expect(scrollIntoView).toHaveBeenCalledTimes(1);
  });

  it('stays in place when loading older messages', async () => {
    const recent = Array.from({ length: 40 }, (_, index) => ({
      ...message(),
      id: String(index + 10),
      content: `Recent ${index}`,
    }));
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/A/messages')) {
          return Promise.resolve({
            data:
              options?.params?.max_id === '10'
                ? [{ ...message(), id: '9', content: 'Older message' }]
                : recent,
          });
        }
        return getResponse(url);
      },
    );
    mountChat();
    await screen.findByText('Recent 39');
    await waitFor(() => {
      expect(scrollIntoView).toHaveBeenCalledTimes(1);
    });
    scrollIntoView.mockClear();

    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText('Older message');

    expect(scrollIntoView).not.toHaveBeenCalled();
  });

  describe('when the messages grow after they are shown', () => {
    let grow: () => void;

    beforeEach(() => {
      grow = () => {
        throw new Error('The messages are not being observed');
      };
      vi.stubGlobal(
        'ResizeObserver',
        class {
          constructor(callback: () => void) {
            grow = callback;
          }
          observe() {
            return undefined;
          }
          disconnect() {
            return undefined;
          }
        },
      );
    });

    it('keeps the newest message in view, as when an image finishes loading', async () => {
      await openRoom();
      scrollIntoView.mockClear();

      grow();

      expect(scrollIntoView).toHaveBeenCalledTimes(1);
    });

    it('does not pull someone reading older messages down', async () => {
      await openRoom();
      scrollTo(3000);
      scrollIntoView.mockClear();

      grow();

      expect(scrollIntoView).not.toHaveBeenCalled();
    });
  });
});

describe('Chat reply indicator', () => {
  const fromRemote = (displayName: string) => ({
    ...message(),
    id: 'theirs',
    content: 'Message to answer',
    account: { ...remote, display_name: displayName },
  });
  const mountReply = (displayName = 'Bob') => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({ data: [fromRemote(displayName)] })
        : getResponse(url),
    );
    return mountChat();
  };
  const replyTo = async (displayName: string) => {
    mountReply(displayName);
    await screen.findByText('Message to answer');
    fireEvent.click(screen.getByRole('button', { name: 'Reply' }));
  };

  it('names the person being answered', async () => {
    await replyTo('Bob');

    expect(screen.getByText('Replying to Bob')).toBeTruthy();
  });

  it('falls back to the handle when the person has no display name', async () => {
    await replyTo('');

    expect(screen.getByText('Replying to bob@remote.test')).toBeTruthy();
  });

  it('says so when the message being answered is deleted', async () => {
    const { container } = mountReply();
    await screen.findByText('Message to answer');
    fireEvent.click(screen.getByRole('button', { name: 'Reply' }));

    act(() => {
      emitChatStreamEvent({
        event: 'chat.message_delete',
        payload: { id: 'theirs', conversation_id: 'A' },
      });
    });

    const indicator = container.querySelector(
      '.chat-native__compose-mode',
    ) as HTMLElement;
    await within(indicator).findByText('This message was deleted.');
    expect(within(indicator).getByText('Replying to Bob')).toBeTruthy();
  });
});

describe('Chat home', () => {
  const home = async () => {
    const view = mountChat('/chat');
    await screen.findByRole('button', { name: 'Search messages' });
    return view;
  };

  it('shows only the tabs and conversations until something is opened', async () => {
    const { container } = await home();

    expect(screen.queryByPlaceholderText('Search messages')).toBeNull();
    expect(screen.queryByPlaceholderText('Group name')).toBeNull();
    expect(screen.queryByPlaceholderText('Search for an account')).toBeNull();
    expect(container.querySelector('.chat-native__new')).toBeNull();
    expect(container.querySelector('.chat-native__conversations')).toBeTruthy();
  });

  it('opens new chats on their own screen from the column header', async () => {
    const { history } = await home();

    fireEvent.click(screen.getByRole('link', { name: 'New chat' }));

    expect(history.location.pathname).toBe('/chat/new');
    expect(
      await screen.findByPlaceholderText('Search for an account'),
    ).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Open chat' })).toBeTruthy();
    expect(screen.queryByPlaceholderText('Group name')).toBeNull();
    expect(screen.queryByRole('link', { name: 'New chat' })).toBeNull();
    expect(api.get).not.toHaveBeenCalledWith(
      '/api/v1/chat/conversations/new',
      expect.anything(),
    );
    expect(api.get).not.toHaveBeenCalledWith('/api/v1/chat/conversations/new');
  });

  it('switches the new chat screen to creating a group, one form at a time', async () => {
    mountChat('/chat/new');
    const group = await screen.findByRole('button', { name: 'Create a group' });

    fireEvent.click(group);

    expect(screen.getByPlaceholderText('Group name')).toBeTruthy();
    expect(
      screen.getAllByPlaceholderText('Search for an account'),
    ).toHaveLength(1);
    expect(screen.queryByRole('button', { name: 'Open chat' })).toBeNull();
    expect(group.getAttribute('aria-pressed')).toBe('true');
  });

  it('opens message search from the header and closes it again', async () => {
    await home();
    const toggle = screen.getByRole('button', { name: 'Search messages' });

    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    fireEvent.click(toggle);
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    const search = screen.getByPlaceholderText('Search messages');
    expect(document.activeElement).toBe(search);

    fireEvent.click(toggle);
    expect(screen.queryByPlaceholderText('Search messages')).toBeNull();
  });

  it('searches with the Enter key and clears results when closed', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/messages/search'
        ? Promise.resolve({ data: [{ ...message(), content: 'Found it' }] })
        : getResponse(url),
    );
    await home();
    const toggle = screen.getByRole('button', { name: 'Search messages' });
    fireEvent.click(toggle);
    const search = screen.getByPlaceholderText('Search messages');
    fireEvent.change(search, { target: { value: 'found' } });
    fireEvent.submit(search.closest('form') as HTMLFormElement);
    expect(await screen.findByText('Found it')).toBeTruthy();

    fireEvent.click(toggle);
    expect(screen.queryByText('Found it')).toBeNull();

    fireEvent.click(toggle);
    expect(
      screen.getByPlaceholderText<HTMLInputElement>('Search messages').value,
    ).toBe('');
  });

  it('sets unread conversations apart from read ones', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations'
        ? Promise.resolve({
            data: [
              { ...conversation('A'), unread: true },
              { ...conversation('B'), unread: false },
            ],
          })
        : getResponse(url),
    );
    const { container } = mountChat('/chat');
    await waitFor(() => {
      expect(
        container.querySelectorAll('.chat-native__conversations button'),
      ).toHaveLength(2);
    });

    const [unread, read] = container.querySelectorAll(
      '.chat-native__conversations button',
    );
    expect(unread?.classList.contains('unread')).toBe(true);
    expect(read?.classList.contains('unread')).toBe(false);
  });
});

describe('Chat invitations', () => {
  const invitation = {
    id: 'inv-1',
    state: 'pending',
    conversation: { ...conversation('C'), type: 'group', title: 'Book club' },
    inviter: remote,
  };
  const openInvitations = async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/invitations'
        ? Promise.resolve({ data: [invitation] })
        : getResponse(url),
    );
    mountChat('/chat');
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );
    await screen.findByText('Book club');
  };

  it('shows the room and who invited, with icon actions like follow requests', async () => {
    await openInvitations();

    expect(screen.getByText('Invited by Bob')).toBeTruthy();
    const accept = screen.getByRole('button', { name: 'Accept' });
    const reject = screen.getByRole('button', { name: 'Reject' });
    expect(accept.classList.contains('icon-button')).toBe(true);
    expect(reject.classList.contains('icon-button')).toBe(true);
    expect(accept.querySelector('svg')).toBeTruthy();
    expect(accept.textContent.trim()).toBe('');
    expect(screen.queryByRole('heading', { name: 'Invitations' })).toBeNull();
  });

  it.each([
    ['Accept', 'accept'],
    ['Reject', 'reject'],
  ])('%s answers the invitation and removes it', async (name, action) => {
    api.post.mockResolvedValue({ data: {} });
    await openInvitations();

    fireEvent.click(screen.getByRole('button', { name }));

    await waitFor(() => {
      expect(api.post).toHaveBeenCalledWith(
        `/api/v1/chat/invitations/inv-1/${action}`,
      );
    });
    await waitFor(() => {
      expect(screen.queryByText('Book club')).toBeNull();
    });
  });
});

describe('Chat composer', () => {
  it('keeps only Send beside the field, with attaching inside the field', async () => {
    const { container } = mountChat();
    await screen.findByText('Private message A');

    const field = container.querySelector('.chat-native__compose-field');
    const attach = screen.getByRole('button', { name: 'Attach media' });
    expect(field?.contains(attach)).toBe(true);
    expect(field?.contains(composer())).toBe(true);
    expect(attach.classList.contains('icon-button')).toBe(true);
    expect(attach.textContent.trim()).toBe('');
    expect(field?.contains(screen.getByRole('button', { name: 'Send' }))).toBe(
      false,
    );
  });

  it('opens the file picker from the attach icon', async () => {
    const { container } = mountChat();
    await screen.findByText('Private message A');
    const input =
      container.querySelector<HTMLInputElement>('input[type="file"]');
    const open = vi.spyOn(input as HTMLInputElement, 'click');

    fireEvent.click(screen.getByRole('button', { name: 'Attach media' }));

    expect(open).toHaveBeenCalled();
  });
});

describe('Chat message actions', () => {
  const theirs = {
    ...message(),
    id: 'theirs',
    content: 'Their message',
    account: remote,
  };
  const mine = { ...message(), id: 'mine', content: 'My message' };
  const mountMessages = async () => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({ data: [theirs, mine] })
        : getResponse(url),
    );
    const view = mountChat();
    await screen.findByText('My message');
    return view;
  };

  it('shows actions as icon buttons outside the bubble', async () => {
    const { container } = await mountMessages();

    const bubbles = container.querySelectorAll('.chat-native__bubble');
    expect(bubbles).toHaveLength(2);
    ['Reply', 'Edit', 'Delete'].forEach((name) => {
      screen.getAllByRole('button', { name }).forEach((button) => {
        expect(button.classList.contains('icon-button')).toBe(true);
        expect(button.querySelector('svg')).toBeTruthy();
        expect(button.textContent.trim()).toBe('');
        bubbles.forEach((bubble) => {
          expect(bubble.contains(button)).toBe(false);
        });
      });
    });
    expect(
      screen.getByText('My message').closest('.chat-native__bubble'),
    ).toBeTruthy();
    expect(container.querySelector('.chat-native__bubble time')).toBeNull();
  });

  it('offers editing and deleting only on my own messages', async () => {
    await mountMessages();

    expect(screen.getAllByRole('button', { name: 'Reply' })).toHaveLength(2);
    expect(screen.getAllByRole('button', { name: 'Edit' })).toHaveLength(1);
    expect(screen.getAllByRole('button', { name: 'Delete' })).toHaveLength(1);
  });

  it('runs each action from its icon', async () => {
    api.delete.mockResolvedValue({ data: {} });
    await mountMessages();

    fireEvent.click(
      screen.getAllByRole('button', { name: 'Reply' })[0] as HTMLElement,
    );
    expect(screen.getByText('Replying to Bob')).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    expect(composer().value).toBe('My message');

    fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
    await waitFor(() => {
      expect(api.delete).toHaveBeenCalledWith('/api/v1/chat/messages/mine');
    });
  });
});

describe('Chat message authors', () => {
  const pictured = {
    ...remote,
    avatar: 'https://remote.test/bob.png',
    avatar_static: 'https://remote.test/bob-static.png',
  };
  const from = (id: string, author: typeof account) => ({
    ...message(),
    id,
    content: `Message ${id}`,
    account: author,
  });
  const mountRun = async () => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({
            data: [
              from('1', pictured),
              from('2', pictured),
              from('3', account),
              from('4', pictured),
            ],
          })
        : getResponse(url),
    );
    const view = mountChat();
    await screen.findByText('Message 4');
    return view;
  };
  const rowOf = (text: string) =>
    screen.getByText(text).closest('.chat-native__message') as HTMLElement;

  it("shows the other person's picture and name at the start of a run", async () => {
    await mountRun();

    expect(rowOf('Message 1').querySelector('.account__avatar')).toBeTruthy();
    expect(within(rowOf('Message 1')).getByText('Bob')).toBeTruthy();
    expect(rowOf('Message 2').querySelector('.account__avatar')).toBeNull();
    expect(within(rowOf('Message 2')).queryByText('Bob')).toBeNull();
    expect(
      rowOf('Message 2').querySelector('.chat-native__avatar-space'),
    ).toBeTruthy();
    expect(rowOf('Message 4').querySelector('.account__avatar')).toBeTruthy();
  });

  it('leaves my own picture and name off my messages', async () => {
    await mountRun();

    expect(rowOf('Message 3').querySelector('.account__avatar')).toBeNull();
    expect(within(rowOf('Message 3')).queryByText('Alice')).toBeNull();
  });
});

describe('Chat home loading', () => {
  it('does not claim there is no history before the list has loaded', async () => {
    const pending = deferred<{ data: ReturnType<typeof conversation>[] }>();
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations' ? pending.promise : getResponse(url),
    );
    mountChat('/chat');
    await screen.findByRole('button', { name: 'Search messages' });

    expect(screen.queryByText('You have no chat history yet.')).toBeNull();

    await act(async () => {
      pending.resolve({ data: [] });
      await pending.promise;
    });
    expect(
      await screen.findByText('You have no chat history yet.'),
    ).toBeTruthy();
  });
});

describe('Chat message runs', () => {
  const at = (id: string, time: string, author: typeof account = remote) => ({
    ...message(),
    id,
    content: `Message ${id}`,
    created_at: time,
    account: author,
  });
  const mountMessages = async (list: ReturnType<typeof at>[]) => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({ data: list })
        : getResponse(url),
    );
    const view = mountChat();
    await screen.findByText(`Message ${list.at(-1)?.id}`);
    return view;
  };
  const rowOf = (text: string) =>
    screen.getByText(text).closest('.chat-native__message') as HTMLElement;

  it('joins messages sent in a row and shows the time once, at the end', async () => {
    await mountMessages([
      at('1', '2026-11-04T01:00:00Z'),
      at('2', '2026-11-04T01:01:00Z'),
      at('3', '2026-11-04T01:02:00Z'),
    ]);

    expect(rowOf('Message 1').classList).not.toContain(
      'chat-native__message--continued',
    );
    expect(rowOf('Message 2').classList).toContain(
      'chat-native__message--continued',
    );
    expect(rowOf('Message 3').classList).toContain(
      'chat-native__message--continued',
    );
    expect(rowOf('Message 1').querySelector('time')).toBeNull();
    expect(rowOf('Message 2').querySelector('time')).toBeNull();
    expect(rowOf('Message 3').querySelector('time')).toBeTruthy();
  });

  it('joins messages up to 17 minutes apart, matching CherryPick', async () => {
    await mountMessages([
      at('1', '2026-11-04T01:00:00Z'),
      at('2', '2026-11-04T01:17:00Z'),
      at('3', '2026-11-04T01:34:01Z'),
    ]);

    expect(rowOf('Message 2').classList).toContain(
      'chat-native__message--continued',
    );
    expect(rowOf('Message 3').classList).not.toContain(
      'chat-native__message--continued',
    );
  });

  it('starts a new run after a long pause or another person', async () => {
    await mountMessages([
      at('1', '2026-11-04T01:00:00Z'),
      at('2', '2026-11-04T01:30:00Z'),
      at('3', '2026-11-04T01:31:00Z', account),
    ]);

    expect(rowOf('Message 1').querySelector('time')).toBeTruthy();
    expect(rowOf('Message 2').classList).not.toContain(
      'chat-native__message--continued',
    );
    expect(rowOf('Message 2').querySelector('.account__avatar')).toBeTruthy();
    expect(rowOf('Message 3').classList).not.toContain(
      'chat-native__message--continued',
    );
  });

  it('shows the date once per day, not on every message', async () => {
    const { container } = await mountMessages([
      at('1', '2026-11-03T12:00:00Z'),
      at('2', '2026-11-03T12:01:00Z'),
      at('3', '2026-11-05T12:00:00Z'),
    ]);

    expect(container.querySelectorAll('.chat-native__date')).toHaveLength(2);
    expect(rowOf('Message 3').querySelector('time')?.textContent).not.toMatch(
      /2026/,
    );
  });

  it('keeps actions in a toolbar that the bubble can reveal without a mouse', async () => {
    const { container } = await mountMessages([
      at('1', '2026-11-04T01:00:00Z'),
    ]);

    const toolbar = container.querySelector('.chat-native__actions');
    expect(
      toolbar?.contains(screen.getByRole('button', { name: 'Reply' })),
    ).toBe(true);
    expect(
      container.querySelector('.chat-native__bubble')?.getAttribute('tabindex'),
    ).toBe('0');
  });
});
