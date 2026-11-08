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
import { CHAT_STREAM_RECONNECTED, emitChatStreamEvent } from '../stream';

const api = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  patch: vi.fn(),
  delete: vi.fn(),
}));
vi.mock('flavours/glitch/api', () => ({ default: () => api }));
const server = vi.hoisted(() => ({ roleplayMode: false }));
vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<typeof InitialState>()),
  me: 'me',
  get roleplayMode() {
    return server.roleplayMode;
  },
}));
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
  ColumnHeader: ({
    title,
    extraButton,
    children,
    onBack,
  }: ColumnHeaderProps) => (
    <header>
      {title}
      {onBack && (
        <button type='button' onClick={onBack}>
          Back
        </button>
      )}
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
  delete_window_hours: 24,
  soft_delete: false,
};
const deferred = <T,>() => {
  let complete!: (value: T) => void;
  const promise = new Promise<T>((resolve) => {
    complete = resolve;
  });
  return { promise, resolve: complete };
};
const answerNextPost = (path: string, answer: Promise<unknown>) => {
  const usual = api.post.getMockImplementation();
  let answered = false;
  api.post.mockImplementation((url: string, ...rest: unknown[]) => {
    if (!answered && url === path) {
      answered = true;
      return answer;
    }
    return usual
      ? (usual(url, ...rest) as Promise<unknown>)
      : Promise.resolve({ data: attachment });
  });
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
  await waitFor(() => {
    expect(lastConfirmation()).toBeTruthy();
  });
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
  if (/^\/api\/v1\/chat\/messages\/[^/]+$/.test(url))
    return Promise.resolve({ data: { deletes_for_everyone: true } });
  throw new Error(`Unexpected GET ${url}`);
};
beforeEach(() => {
  vi.resetAllMocks();
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
    function (this: Element) {
      if (this.classList.contains('chat-native__composer'))
        return { top: 500, bottom: 550 } as DOMRect;
      return { top: 100, bottom: 150 } as DOMRect;
    },
  );
  api.get.mockImplementation(getResponse);
  api.post.mockResolvedValue({ data: attachment });
  api.delete.mockResolvedValue({ data: {} });
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

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
      fireEvent.change(composer(), { target: { value: 'Private draft A' } });
      upload(container);
      await screen.findByAltText('Private attachment A');
      if (mode !== 'draft')
        fireEvent.click(
          screen.getByRole('button', {
            name: mode === 'edit' ? 'Edit' : 'Reply',
          }),
        );

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
      answerNextPost(
        '/api/v1/chat/conversations/B/messages',
        Promise.resolve({
          data: { ...message('B'), id: 'sent-B', content: 'Hello B' },
        }),
      );
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
        expect(
          screen.getByRole('img', { name: '🎉 @bob@remote.test' }),
        ).toBeTruthy();
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
        expect(
          screen.getByRole('img', { name: '🎉 @bob@remote.test' }),
        ).toBeTruthy();
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
    expect(
      screen.getByRole('img', { name: '🎉 @bob@remote.test' }),
    ).toBeTruthy();
    act(() => {
      emitChatStreamEvent({
        event: 'chat.message_delete',
        payload: { id: 'message-A', conversation_id: 'A' },
      });
    });
    expect(screen.getByText('This message was deleted.')).toBeTruthy();
    expect(screen.queryByText('Private message A')).toBeNull();
    expect(screen.queryByAltText('Private attachment A')).toBeNull();
    expect(
      screen.queryByRole('img', { name: '🎉 @bob@remote.test' }),
    ).toBeNull();
    act(() => {
      emitChatStreamEvent({ event: 'chat.reaction', payload: reaction });
    });
    expect(
      screen.queryByRole('img', { name: '🎉 @bob@remote.test' }),
    ).toBeNull();
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
          emitChatStreamEvent({ event: CHAT_STREAM_RECONNECTED, payload: {} });
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
      expect(
        screen.queryByRole('img', { name: '🎉 @bob@remote.test' }),
      ).toBeNull();
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
        answerNextPost(
          '/api/v1/chat/conversations/A/messages',
          pending.promise,
        );
      }
      fireEvent.change(composer(), { target: { value: 'Delayed content' } });
      fireEvent.click(
        screen.getByRole('button', {
          name: operation === 'edit' ? 'Save' : 'Send',
        }),
      );
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
      expect(
        screen.queryByRole('img', { name: '🎉 @bob@remote.test' }),
      ).toBeNull();
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
      expect(
        screen.queryByRole('img', { name: '🎉 @bob@remote.test' }),
      ).toBeNull();
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
    expect(
      screen.queryByRole('img', { name: '🎉 @bob@remote.test' }),
    ).toBeNull();
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
    answerNextPost(
      '/api/v1/chat/messages/message-A/reactions',
      pending.promise,
    );
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
    expect(
      screen.getAllByRole('img', { name: '🎉 @bob@remote.test' }),
    ).toHaveLength(1);
    expect(screen.getByRole('img', { name: '🎉 @bob@remote.test' }).title).toBe(
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
    expect(screen.queryByText('💥')).toBeNull();
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
    expect(screen.queryByText('🎉')).toBeNull();
  });

  it('offers only your own reactions as buttons, saying they are yours', async () => {
    mountChat();
    await screen.findByText('Private message A');
    act(() => {
      emitChatStreamEvent({ event: 'chat.reaction', payload: reaction });
      emitChatStreamEvent({
        event: 'chat.reaction',
        payload: { ...reaction, reaction: '👍', account },
      });
    });

    expect(screen.queryByRole('button', { name: '🎉' })).toBeNull();
    expect(
      screen.getByRole('button', { name: '👍' }).getAttribute('aria-pressed'),
    ).toBe('true');
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
    expect(api.delete).not.toHaveBeenCalled();
    await confirmModal();

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

    const save = screen.getByRole<HTMLButtonElement>('button', {
      name: 'Save',
    });
    expect(save.disabled).toBe(false);
    fireEvent.click(save);

    await waitFor(() => {
      expect(screen.queryByText('Editing message')).toBeNull();
    });
    expect(api.patch).toHaveBeenCalledWith('/api/v1/chat/messages/message-A', {
      text: '',
    });
    expect(screen.queryByText('Private message A')).toBeNull();
    expect(screen.getByAltText('Private attachment A')).toBeTruthy();
    expect(save.disabled).toBe(true);
  });

  it('keeps empty text-only edits disabled', async () => {
    mountChat();
    await screen.findByText('Private message A');
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    fireEvent.change(composer(), { target: { value: '   ' } });

    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Save' }).disabled,
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

    const shown = screen.getByRole('img', {
      name: ':blobcat: @bob@remote.test',
    });
    expect(shown.querySelector('img.emoji')?.getAttribute('alt')).toBe(
      ':blobcat:',
    );
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
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

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
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));
    await screen.findByRole('alert');

    fireEvent.click(screen.getByRole('button', { name: 'Save' }));

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
        payload: { ...live },
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
        payload: { ...live },
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
        payload: { ...live },
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
    expect(api.get).not.toHaveBeenCalledWith(
      '/api/v1/chat/conversations/A/messages',
    );
    expect(api.post).not.toHaveBeenCalledWith(
      '/api/v1/chat/conversations/A/read',
    );

    setVisibility('visible');
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });

    await screen.findByText('Private message A');
    await waitFor(() => {
      expect(api.post).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/A/read',
        { message_id: 'message-A' },
      );
    });
  });

  it('coalesces reconnects while a conversation list response is on its way', async () => {
    const older = deferred<{ data: unknown }>();
    const newer = deferred<{ data: unknown }>();
    let requests = 0;
    api.get.mockImplementation((url: string) => {
      if (url !== '/api/v1/chat/conversations') return getResponse(url);
      requests += 1;
      if (requests === 2) return older.promise;
      if (requests === 3) return newer.promise;
      return Promise.resolve({
        data: [{ ...conversation('A'), title: `Version ${requests}` }],
      });
    });

    mountChat();
    await screen.findByText('Version 1');
    act(() => {
      emitChatStreamEvent({ event: CHAT_STREAM_RECONNECTED, payload: {} });
      emitChatStreamEvent({ event: CHAT_STREAM_RECONNECTED, payload: {} });
    });
    expect(screen.getByText('Version 1')).toBeTruthy();
    expect(requests).toBe(2);

    await act(async () => {
      older.resolve({
        data: [{ ...conversation('A'), title: 'Old version' }],
      });
      await Promise.resolve();
    });

    await waitFor(() => {
      expect(requests).toBe(3);
    });
    expect(screen.queryByText('Old version')).toBeNull();
    expect(screen.getByText('Version 1')).toBeTruthy();
    await act(async () => {
      newer.resolve({
        data: [{ ...conversation('A'), title: 'Version 3' }],
      });
      await Promise.resolve();
    });
    await screen.findByText('Version 3');
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
    expect(screen.getByText(/This message is too long/)).toBeTruthy();
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

    mountChat('/chat');
    await screen.findByText('Room A');

    expect(screen.getByRole('img', { name: 'Unread messages' })).toBeTruthy();
    expect(
      screen.getByRole('button', { name: /Room A.*Unread messages/ }),
    ).toBeTruthy();
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

  it('leaves deleting a group out of the menu on a roleplay server', async () => {
    server.roleplayMode = true;
    try {
      respondWith(room());
      mountChat();
      await screen.findByText('Private message A');

      expect(screen.getByRole('button', { name: 'Archive' })).toBeTruthy();
      expect(screen.queryByRole('button', { name: 'Delete group' })).toBeNull();
    } finally {
      server.roleplayMode = false;
    }
  });

  it('still lets members leave a group on a roleplay server', async () => {
    server.roleplayMode = true;
    try {
      respondWith(room('A', 'member'));
      mountChat();
      await screen.findByText('Private message A');

      expect(screen.getByRole('button', { name: 'Leave group' })).toBeTruthy();
    } finally {
      server.roleplayMode = false;
    }
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
    expect(
      (await screen.findByPlaceholderText('Group name')).getAttribute('name'),
    ).toBe('search');
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
          id: 'message-A-live',
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

  it('keeps the reading position for my own new message when scrolled up', async () => {
    await openRoom();
    scrollTo(3000);
    scrollIntoView.mockClear();

    liveMessage(account);
    await screen.findByText('Live message');

    expect(scrollIntoView).not.toHaveBeenCalled();
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

  it('searches as the user types, using only the latest text', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/messages/search'
        ? Promise.resolve({ data: [{ ...message(), content: 'Found it' }] })
        : getResponse(url),
    );
    await home();
    fireEvent.click(screen.getByRole('button', { name: 'Search messages' }));
    const search = screen.getByPlaceholderText('Search messages');
    fireEvent.change(search, { target: { value: 'fo' } });
    fireEvent.change(search, { target: { value: 'found' } });

    expect(await screen.findByText('Found it')).toBeTruthy();
    const searches = api.get.mock.calls.filter(
      ([url]) => url === '/api/v1/chat/messages/search',
    );
    expect(searches).toHaveLength(1);
    expect(searches[0]?.[1]).toMatchObject({ params: { q: 'found' } });

    fireEvent.change(search, { target: { value: '' } });
    expect(screen.queryByText('Found it')).toBeNull();
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

  it('shows the room and who invited, with the actions in words', async () => {
    await openInvitations();

    expect(screen.getByText('Invited by Bob')).toBeTruthy();
    const accept = screen.getByRole('button', { name: 'Accept' });
    const reject = screen.getByRole('button', { name: 'Reject' });
    expect(accept.textContent).toBe('Accept');
    expect(reject.textContent).toBe('Reject');
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
    await confirmModal();
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
    ).toBe('-1');
  });
});

describe('Chat back button', () => {
  it.each([
    ['/chat/A', '/chat'],
    ['/chat/new', '/chat'],
    ['/chat/A/members', '/chat/A'],
    ['/chat/A/settings', '/chat/A'],
  ])('goes from %s up to %s', async (from, to) => {
    const { history } = mountChat(from);

    fireEvent.click(await screen.findByRole('button', { name: 'Back' }));

    expect(history.location.pathname).toBe(to);
  });

  const back = async () => {
    fireEvent.click(await screen.findByRole('button', { name: 'Back' }));
  };

  it('returns to the list entry it came from instead of adding one', async () => {
    const { history } = mountChat('/chat');
    await screen.findByRole('button', { name: /Room A/ });
    navigate(history, '/chat/A');
    await screen.findByText('Private message A');

    await back();

    expect(history.location.pathname).toBe('/chat');
    expect(history.index).toBe(0);
    expect(history.length).toBe(2);
  });

  it('walks back through a room view and the room to the list', async () => {
    const { history } = mountChat('/chat');
    await screen.findByRole('button', { name: /Room A/ });
    navigate(history, '/chat/A');
    navigate(history, '/chat/A/members');

    await back();
    expect(history.location.pathname).toBe('/chat/A');
    expect(history.index).toBe(1);

    await back();
    expect(history.location.pathname).toBe('/chat');
    expect(history.index).toBe(0);
  });

  it('replaces a room reached from elsewhere with the list', async () => {
    const { history } = mountChat('/home');
    navigate(history, '/chat/A');
    await screen.findByText('Private message A');

    await back();

    expect(history.location.pathname).toBe('/chat');
    expect(history.length).toBe(2);
    act(() => {
      history.goBack();
    });
    expect(history.location.pathname).toBe('/home');
  });

  it('puts a new room in place of the new chat screen', async () => {
    const { history } = mountChat('/chat');
    await screen.findByRole('button', { name: /Room A/ });
    navigate(history, '/chat/new');
    fireEvent.click(
      await screen.findByRole('button', { name: 'Create a group' }),
    );
    const title = screen.getByPlaceholderText('Group name');
    fireEvent.change(title, { target: { value: 'Hikers' } });
    answerNextPost(
      '/api/v1/chat/conversations',
      Promise.resolve({
        data: { ...conversation('A'), type: 'group', title: 'Hikers' },
      }),
    );
    const form = title.closest('form');
    if (!form) throw new Error('Missing group form');
    fireEvent.submit(form);

    await waitFor(() => {
      expect(history.location.pathname).toBe('/chat/A');
    });
    expect(history.length).toBe(2);

    await back();
    expect(history.location.pathname).toBe('/chat');
    expect(history.index).toBe(0);
  });

  it('steps back off a room deleted while it was open', async () => {
    const { history } = mountChat('/chat');
    await screen.findByRole('button', { name: /Room A/ });
    navigate(history, '/chat/A');
    await screen.findByText('Private message A');

    act(() => {
      emitChatStreamEvent({
        event: 'chat.conversation_delete',
        payload: { conversation_id: 'A' },
      });
    });

    expect(history.location.pathname).toBe('/chat');
    expect(history.index).toBe(0);
  });
});

describe('Chat sending with the keyboard', () => {
  const typeAndPress = async (init: KeyboardEventInit) => {
    mountChat();
    await screen.findByText('Private message A');
    fireEvent.change(composer(), { target: { value: 'Typed' } });
    fireEvent.keyDown(composer(), { key: 'Enter', ...init });
  };
  const sentMessages = () =>
    api.post.mock.calls.filter(([url]) => String(url).endsWith('/messages'));

  beforeEach(() => {
    api.post.mockResolvedValue({ data: { ...message(), id: 'sent' } });
  });

  it('sends on Enter', async () => {
    await typeAndPress({});
    await waitFor(() => {
      expect(sentMessages()).toHaveLength(1);
    });
  });

  it('stays writable while sending and does not send twice', async () => {
    const sending = deferred<{ data: unknown }>();
    api.post.mockImplementation((url: string) =>
      url.endsWith('/messages')
        ? sending.promise
        : Promise.resolve({ data: {} }),
    );
    await typeAndPress({});
    await waitFor(() => {
      expect(sentMessages()).toHaveLength(1);
    });
    expect(composer().readOnly).toBe(false);
    expect(composer().disabled).toBe(false);

    fireEvent.keyDown(composer(), { key: 'Enter' });
    expect(sentMessages()).toHaveLength(1);

    await act(async () => {
      sending.resolve({ data: { ...message(), id: 'sent' } });
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(composer().value).toBe('');
    });
    expect(composer().readOnly).toBe(false);
  });

  it('keeps Shift+Enter for a new line', async () => {
    await typeAndPress({ shiftKey: true });
    expect(sentMessages()).toHaveLength(0);
  });

  it('does not send when Enter confirms Korean input', async () => {
    await typeAndPress({ isComposing: true });
    expect(sentMessages()).toHaveLength(0);
  });

  it('keeps Enter for a new line on touch keyboards', async () => {
    vi.stubGlobal('matchMedia', () => ({ matches: true }));
    await typeAndPress({});
    expect(sentMessages()).toHaveLength(0);
    vi.unstubAllGlobals();
  });
});

describe('Chat reply quote', () => {
  const original = {
    ...message(),
    id: 'original',
    content: 'The question',
    account: { ...remote, display_name: 'Bob' },
  };
  const answer = {
    ...message(),
    id: 'answer',
    content: 'The answer',
    reply_to_id: 'original',
  };
  const mountWith = async (list: unknown[]) => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({ data: list })
        : getResponse(url),
    );
    const view = mountChat();
    await screen.findByText('The answer');
    return view;
  };

  it('shows who and what a sent reply answers', async () => {
    const { container } = await mountWith([original, answer]);

    const quote = container.querySelector('.chat-native__reply-quote');
    expect(quote?.textContent).toContain('Bob');
    expect(quote?.textContent).toContain('The question');
  });

  it('still marks a reply whose original is not loaded', async () => {
    const { container } = await mountWith([answer]);

    expect(
      container.querySelector('.chat-native__reply-quote')?.textContent,
    ).toContain('Replying to message');
  });

  it('highlights the original when the quote is clicked', async () => {
    const { container } = await mountWith([original, answer]);

    fireEvent.click(
      container.querySelector('.chat-native__reply-quote') as Element,
    );

    expect(
      container.querySelector('#chat-message-original')?.classList,
    ).toContain('chat-native__message--highlighted');
  });
});

describe('Chat search results', () => {
  it('opens the room at the message, loading older pages to reach it', async () => {
    const page = (from: number) =>
      Array.from({ length: 40 }, (_, index) => ({
        ...message(),
        id: String(from + index),
        content: `Message ${from + index}`,
      }));
    api.get.mockImplementation(
      (url: string, config?: { params?: { max_id?: string } }) => {
        if (!url.includes('/A/messages')) return getResponse(url);
        return Promise.resolve({
          data: config?.params?.max_id ? page(100) : page(200),
        });
      },
    );
    const history = createMemoryHistory({
      initialEntries: [
        { pathname: '/chat/A', state: { chatMessageId: '105' } },
      ],
    });
    const { container } = render(
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

    await screen.findByText('Message 105');

    expect(container.querySelector('#chat-message-105')?.classList).toContain(
      'chat-native__message--highlighted',
    );
  });
});

describe('Chat jump to newest', () => {
  const scrollIntoView = vi.fn();
  const openRoom = async () => {
    mountChat();
    await screen.findByText('Private message A');
    await waitFor(() => {
      expect(scrollIntoView).toHaveBeenCalled();
    });
  };
  const scrollAway = () => {
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
      bottom: window.innerHeight + 5000,
    } as DOMRect);
    fireEvent.scroll(window);
  };
  const receive = () => {
    act(() => {
      emitChatStreamEvent({
        event: 'chat.message',
        payload: {
          ...message(),
          id: 'message-A-live',
          content: 'Live message',
          account: remote,
        },
      });
    });
  };

  beforeEach(() => {
    scrollIntoView.mockClear();
    Element.prototype.scrollIntoView = scrollIntoView;
  });

  afterEach(() => {
    Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
    vi.restoreAllMocks();
  });

  it('offers a way back only after scrolling away', async () => {
    await openRoom();
    expect(
      screen.queryByRole('button', { name: 'Jump to newest message' }),
    ).toBeNull();

    scrollAway();

    expect(
      screen.getByRole('button', { name: 'Jump to newest message' }),
    ).toBeTruthy();
  });

  it('says so when a message arrives while reading older ones', async () => {
    await openRoom();
    scrollAway();

    receive();

    expect(screen.getByText('New messages')).toBeTruthy();
  });

  it('clears the notice after jumping back', async () => {
    await openRoom();
    scrollAway();
    receive();

    fireEvent.click(screen.getByRole('button', { name: 'New messages' }));

    expect(screen.queryByText('New messages')).toBeNull();
  });
});

describe('Chat room ending', () => {
  const NOTICES = [
    ['deleted', 'This group was deleted.'],
    [
      'removed',
      'You have left this group. An invitation is required to rejoin.',
    ],
  ] as const;
  const close = (reason?: string) => {
    act(() => {
      emitChatStreamEvent({
        event: 'chat.conversation_delete',
        payload: { conversation_id: 'A', reason },
      });
    });
  };
  const roomIsGone = (reason?: string) => {
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({ data: [] });
      if (url === '/api/v1/chat/conversations/A' || url.endsWith('/messages'))
        return Promise.reject(
          Object.assign(new Error('Not found'), {
            response: {
              status: 404,
              data: { error: 'Record not found', reason },
            },
          }),
        );
      return getResponse(url);
    });
  };

  it.each(NOTICES)(
    'says the group was %s while it was open',
    async (reason, notice) => {
      const { history } = mountChat();
      await screen.findByText('Private message A');

      close(reason);

      expect(screen.getByText(notice)).toBeTruthy();
      expect(screen.queryByText('Private message A')).toBeNull();
      expect(screen.queryByPlaceholderText('Write a message')).toBeNull();
      expect(history.location.pathname).toBe('/chat/A');

      fireEvent.click(screen.getByRole('link', { name: 'Back to chats' }));

      expect(history.location.pathname).toBe('/chat');
    },
  );

  it.each(NOTICES)(
    'says the group was %s when its address is opened again',
    async (reason, notice) => {
      roomIsGone(reason);

      mountChat();

      expect(await screen.findByText(notice)).toBeTruthy();
      await waitFor(() => {
        expect(api.get).toHaveBeenCalledWith(
          '/api/v1/chat/conversations/A/messages',
        );
      });
      expect(screen.queryByRole('alert')).toBeNull();
    },
  );

  it('keeps the error for an address nobody said anything about', async () => {
    roomIsGone();

    mountChat();

    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(screen.queryByRole('link', { name: 'Back to chats' })).toBeNull();
  });

  it('goes to the list without a word for whoever deleted it', async () => {
    const { history } = mountChat();
    await screen.findByText('Private message A');

    close();

    expect(history.location.pathname).toBe('/chat');
    expect(screen.queryByRole('link', { name: 'Back to chats' })).toBeNull();
  });

  it('does not reopen the group for an answer from before it ended', async () => {
    mountChat();
    await screen.findByText('Private message A');
    const earlier = deferred<{ data: unknown }>();
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations' ? earlier.promise : getResponse(url),
    );
    act(() => {
      emitChatStreamEvent({ event: CHAT_STREAM_RECONNECTED, payload: {} });
    });

    close('removed');
    await act(async () => {
      earlier.resolve(await getResponse('/api/v1/chat/conversations'));
    });

    expect(screen.getByRole('link', { name: 'Back to chats' })).toBeTruthy();
    expect(screen.queryByPlaceholderText('Write a message')).toBeNull();
  });
});

describe('Chat account search', () => {
  it('says when no account matched', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    api.get.mockImplementation((url: string) =>
      url === '/api/v2/search'
        ? Promise.resolve({ data: { accounts: [] } })
        : getResponse(url),
    );
    mountChat('/chat/new');
    const input = await screen.findByPlaceholderText(/search/i);

    fireEvent.change(input, { target: { value: 'nobody' } });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(300);
    });

    expect(screen.getByText('No accounts found.')).toBeTruthy();
    vi.useRealTimers();
  });
});

describe('Chat deletion notice', () => {
  const HOUR = 3_600_000;
  const everyone =
    "It will show as deleted for everyone in this chat. This can't be undone.";
  const onlyYou =
    "It will disappear only for you. Others in this chat can still see it. This can't be undone.";
  const unknown =
    "It may disappear for everyone or only for you, depending on this server's settings. This can't be undone.";
  const noticeFor = async (
    serverAnswer: () => Promise<{ data: unknown }>,
    age = 0,
  ) => {
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/messages/message-A') return serverAnswer();
      if (url.endsWith('/messages'))
        return Promise.resolve({
          data: [
            {
              ...message(),
              created_at: new Date(Date.now() - age).toISOString(),
            },
          ],
        });
      return getResponse(url);
    });
    mountChat();
    await screen.findByText('Private message A');
    dispatch.mockClear();
    fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
    await waitFor(() => {
      expect(dispatch).toHaveBeenCalled();
    });
    return lastConfirmation()?.message;
  };

  it('promises removal for everyone when the server says so, whatever the browser clock says', async () => {
    expect(
      await noticeFor(
        () => Promise.resolve({ data: { deletes_for_everyone: true } }),
        25 * HOUR,
      ),
    ).toBe(everyone);
  });

  it('says others keep the message when the server says so, whatever the browser clock says', async () => {
    expect(
      await noticeFor(() =>
        Promise.resolve({ data: { deletes_for_everyone: false } }),
      ),
    ).toBe(onlyYou);
  });

  it('promises neither when the server cannot be asked', async () => {
    expect(await noticeFor(() => Promise.reject(new Error('offline')))).toBe(
      unknown,
    );
  });
});

describe('Chat message ordering', () => {
  it('keeps incoming messages in ID order when broadcasts arrive out of order', async () => {
    api.get.mockImplementation((url: string) =>
      url.endsWith('/messages')
        ? Promise.resolve({ data: [] })
        : getResponse(url),
    );
    const { container } = mountChat();
    await screen.findByPlaceholderText('Write a message');

    act(() => {
      for (const id of ['102', '101'])
        emitChatStreamEvent({
          event: 'chat.message',
          payload: { ...message(), id, content: `Message ${id}` },
        });
    });

    expect(
      Array.from(container.querySelectorAll('.chat-native__message')).map(
        (item) => item.id,
      ),
    ).toEqual(['chat-message-101', 'chat-message-102']);
  });

  it('inserts a delayed send response before a newer streamed message', async () => {
    api.get.mockImplementation((url: string) =>
      url.endsWith('/messages')
        ? Promise.resolve({ data: [] })
        : getResponse(url),
    );
    const pending = deferred<{ data: ReturnType<typeof message> }>();
    answerNextPost('/api/v1/chat/conversations/A/messages', pending.promise);
    const { container } = mountChat();
    await screen.findByPlaceholderText('Write a message');
    fireEvent.change(composer(), { target: { value: 'Sent message' } });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));

    await act(async () => {
      emitChatStreamEvent({
        event: 'chat.message',
        payload: { ...message(), id: '102', content: 'Newer message' },
      });
      pending.resolve({
        data: { ...message(), id: '101', content: 'Sent message' },
      });
      await pending.promise;
    });

    expect(
      Array.from(container.querySelectorAll('.chat-native__message')).map(
        (item) => item.id,
      ),
    ).toEqual(['chat-message-101', 'chat-message-102']);
  });

  it('keeps a newer conversation preview after an older creation event', async () => {
    mountChat('/chat');
    await screen.findByText('Room A');

    act(() => {
      for (const id of ['102', '101'])
        emitChatStreamEvent({
          event: 'chat.message',
          payload: { ...message(), id, content: `Message ${id}` },
        });
    });

    expect(screen.getByText('Message 102')).toBeTruthy();
    expect(screen.queryByText('Message 101')).toBeNull();
  });
});

describe('Chat stream resynchronisation', () => {
  const messageRequests = () =>
    api.get.mock.calls.filter(([url]) => String(url).endsWith('/messages'));

  it.each(['chat.member_join', 'chat.member_leave'])(
    'keeps the loaded messages on %s',
    async (event) => {
      mountChat();
      await screen.findByText('Private message A');
      const requests = messageRequests().length;

      await act(async () => {
        emitChatStreamEvent({
          event,
          payload: { conversation_id: 'A', account_id: 'remote' },
        });
        await Promise.resolve();
      });

      expect(messageRequests()).toHaveLength(requests);
    },
  );

  it('fetches what it missed when the stream reconnects', async () => {
    mountChat();
    await screen.findByText('Private message A');
    api.get.mockImplementation((url: string) =>
      url.endsWith('/messages')
        ? Promise.resolve({
            data: [
              message(),
              { ...message(), id: 'missed', content: 'Missed while offline' },
            ],
          })
        : getResponse(url),
    );

    act(() => {
      emitChatStreamEvent({ event: CHAT_STREAM_RECONNECTED, payload: {} });
    });

    expect(await screen.findByText('Missed while offline')).toBeTruthy();
  });

  describe('while reading older pages', () => {
    const page = (from: number, label = 'Message') =>
      Array.from({ length: 40 }, (_, index) => ({
        ...message(),
        id: String(from + index),
        content: `${label} ${from + index}`,
      }));
    const older = { ...message(), id: '90', content: 'Older page' };
    const serve = (
      newest: { id: string; content: string | null }[],
      byCursor: Record<string, { id: string; content: string | null }[]> = {},
    ) => {
      api.get.mockImplementation(
        (url: string, options?: { params?: { max_id?: string } }) => {
          if (url.endsWith('/A/messages')) {
            const cursor = options?.params?.max_id;
            return Promise.resolve({
              data: cursor ? (byCursor[cursor] ?? []) : newest,
            });
          }
          return getResponse(url);
        },
      );
    };
    const openWithOlderPage = async () => {
      serve(page(100), { '100': [older] });
      mountChat();
      await screen.findByText('Message 139');
      fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
      await screen.findByText('Older page');
    };
    const reconnect = async () => {
      await act(async () => {
        emitChatStreamEvent({ event: CHAT_STREAM_RECONNECTED, payload: {} });
        await new Promise((resolve) => setTimeout(resolve));
      });
    };

    it('keeps the older page and adds what it missed', async () => {
      await openWithOlderPage();
      serve(
        [...page(100).slice(1), { ...message(), id: '140', content: 'Missed' }],
        { '101': [older, ...page(100).slice(0, 1)] },
      );

      await reconnect();

      expect(screen.getByText('Older page')).toBeTruthy();
      expect(screen.getByText('Message 100')).toBeTruthy();
      expect(screen.getByText('Missed')).toBeTruthy();
    });

    it('applies edits and removals among the messages it fetched again', async () => {
      await openWithOlderPage();
      const fresh = page(100).filter((item) => item.id !== '120');
      serve([
        older,
        ...fresh.map((item) =>
          item.id === '121' ? { ...item, content: 'Edited offline' } : item,
        ),
      ]);

      await reconnect();

      expect(screen.getByText('Edited offline')).toBeTruthy();
      expect(screen.queryByText('Message 120')).toBeNull();
      expect(screen.getByText('Older page')).toBeTruthy();
    });

    it('refreshes edits in already loaded older pages after reconnecting', async () => {
      await openWithOlderPage();
      serve(page(100), {
        '100': [{ ...older, content: 'Older page edited offline' }],
      });

      await reconnect();

      expect(await screen.findByText('Older page edited offline')).toBeTruthy();
      expect(screen.queryByText('Older page')).toBeNull();
    });

    it('removes hidden messages from already loaded older pages after reconnecting', async () => {
      await openWithOlderPage();
      serve(page(100), { '100': [] });

      await reconnect();

      await waitFor(() => {
        expect(screen.queryByText('Older page')).toBeNull();
      });
    });

    it('pages back until it meets what it has, so nothing is left out', async () => {
      await openWithOlderPage();
      serve(page(220, 'Newest'), {
        '220': page(180, 'Middle'),
        '180': page(135, 'Bridge'),
        '135': [older, ...page(100).slice(0, 35)],
      });

      await reconnect();

      expect(screen.getByText('Newest 259')).toBeTruthy();
      expect(screen.getByText('Middle 180')).toBeTruthy();
      expect(screen.getByText('Bridge 135')).toBeTruthy();
      expect(screen.getByText('Older page')).toBeTruthy();
    });

    it('refreshes more than 25 already loaded pages without discarding them', async () => {
      serve(page(100));
      mountChat();
      await screen.findByText('Message 139');
      act(() => {
        for (let id = 140; id < 1140; id++)
          emitChatStreamEvent({
            event: 'chat.message',
            payload: { ...message(), id: String(id), content: `Message ${id}` },
          });
      });
      await screen.findByText('Message 1139');
      const olderPages = Object.fromEntries(
        Array.from({ length: 25 }, (_, index) => {
          const cursor = 1100 - index * 40;
          return [String(cursor), page(cursor - 40)];
        }),
      );
      olderPages['140'] = page(100).map((item) =>
        item.id === '100'
          ? { ...item, content: 'Oldest changed offline' }
          : item,
      );
      serve(page(1100), olderPages);

      await reconnect();

      expect(await screen.findByText('Oldest changed offline')).toBeTruthy();
      expect(screen.getByText('Message 1139')).toBeTruthy();
    }, 30_000);

    it('starts over from the newest page when too much was missed', async () => {
      await openWithOlderPage();
      const endless = Object.fromEntries(
        Array.from({ length: 30 }, (_, index) => [
          String(1000 + (index + 1) * 40),
          page(1000 + index * 40, 'Filler'),
        ]),
      );
      serve(page(2240, 'Newest'), { ...endless, '2240': page(2200, 'Filler') });

      await reconnect();

      expect(screen.getByText('Newest 2279')).toBeTruthy();
      expect(screen.queryByText('Older page')).toBeNull();
      expect(screen.getByRole('button', { name: 'Load more' })).toBeTruthy();
    });

    it('still offers older pages after merging', async () => {
      const full = page(100);
      serve(full, { '100': page(60, 'Older') });
      mountChat();
      await screen.findByText('Message 139');
      fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
      await screen.findByText('Older 60');

      serve(full, {
        '100': page(60, 'Older'),
        '60': [{ ...older, id: '59' }],
      });
      await reconnect();
      fireEvent.click(screen.getByRole('button', { name: 'Load more' }));

      expect(await screen.findByText('Older page')).toBeTruthy();
    });

    it('does not mark the conversation read while the reader is elsewhere', async () => {
      await openWithOlderPage();
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
        bottom: window.innerHeight + 5000,
      } as DOMRect);
      fireEvent.scroll(window);
      api.post.mockClear();
      serve([
        ...page(100).slice(1),
        {
          ...message(),
          id: '140',
          content: 'Missed',
          account: { ...account, id: 'someone-else' },
        },
      ]);

      await reconnect();

      expect(screen.getByText('Missed')).toBeTruthy();
      expect(
        api.post.mock.calls.filter(([url]) => String(url).endsWith('/read')),
      ).toHaveLength(0);
      vi.restoreAllMocks();
    });

    it('stays quiet when a refresh fails, because the next one tries again', async () => {
      await openWithOlderPage();
      api.get.mockImplementation(() => Promise.reject(new Error('offline')));

      await reconnect();

      expect(
        screen.queryByText('The chat request could not be completed.'),
      ).toBeNull();
      expect(screen.getByText('Older page')).toBeTruthy();
    });
  });
});

describe('Chat confirmations', () => {
  const alertMessages = () =>
    dispatch.mock.calls.map(
      ([action]) =>
        (action as { payload?: { message?: { id?: string } } }).payload?.message
          ?.id,
    );
  const ownedGroup = {
    ...conversation('A'),
    type: 'group',
    current_role: 'owner',
  };
  const mountGroup = (path: string) => {
    dispatch.mockClear();
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations/A')
        return Promise.resolve({ data: ownedGroup });
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({ data: [ownedGroup], headers: {} });
      if (url === '/api/v2/search')
        return Promise.resolve({ data: { accounts: [remote] } });
      return getResponse(url);
    });
    return mountChat(path);
  };

  it('confirms saved group settings', async () => {
    api.patch.mockResolvedValue({ data: ownedGroup });
    const { container } = mountGroup('/chat/A/settings');
    await waitFor(() => {
      expect(container.querySelector('.chat-native__group-edit')).toBeTruthy();
    });

    fireEvent.submit(
      container.querySelector('.chat-native__group-edit') as Element,
    );

    await waitFor(() => {
      expect(alertMessages()).toContain('chat.group_saved');
    });
  });

  it('shows an archived group as a notice in the composer, not an error', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations'
        ? Promise.resolve({
            data: [{ ...conversation('A'), type: 'group', archived: true }],
            headers: {},
          })
        : getResponse(url),
    );
    const { container } = mountChat();

    const notice = await screen.findByText('This group is archived.');

    expect(notice.closest('.chat-native__notice')).toBeTruthy();
    expect(
      container.querySelector('.chat-native__composer')?.contains(notice),
    ).toBe(true);
  });
});

describe('Chat attachments', () => {
  const pictures = [1, 2, 3, 4].map((index) => ({
    id: `media-${index}`,
    url: `/full-${index}.png`,
    preview_url: `/small-${index}.png`,
    type: 'image',
    description: `Picture ${index}`,
  }));
  const mountWith = async (attachments: unknown[]) => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({
            data: [{ ...message(), media_attachments: attachments }],
          })
        : getResponse(url),
    );
    const view = mountChat();
    await screen.findByText('Private message A');
    return view;
  };
  const uploadFiles = (container: HTMLElement, count: number) => {
    const input = container.querySelector('input[type="file"]');
    if (!input) throw new Error('Missing attachment input');
    fireEvent.change(input, {
      target: {
        files: Array.from(
          { length: count },
          (_, index) =>
            new File(['private'], `${index}.png`, { type: 'image/png' }),
        ),
      },
    });
  };

  it('shows the attachments of a message in the gallery posts use', async () => {
    const { container } = await mountWith(pictures);

    expect(container.querySelector('.media-gallery--layout-4')).toBeTruthy();
    pictures.forEach(({ description }) => {
      expect(screen.getByAltText(description)).toBeTruthy();
    });
  });

  it('opens the picture that was clicked, with the others to browse', async () => {
    await mountWith(pictures);
    dispatch.mockClear();

    fireEvent.click(screen.getByAltText('Picture 2'));

    const action = dispatch.mock.lastCall?.[0] as {
      payload: {
        modalType: string;
        modalProps: { index: number; media: { size: number } };
      };
    };
    expect(action.payload.modalType).toBe('MEDIA');
    expect(action.payload.modalProps.index).toBe(1);
    expect(action.payload.modalProps.media.size).toBe(4);
  });

  it('plays audio outside the gallery, which cannot show it', async () => {
    const { container } = await mountWith([
      pictures[0],
      {
        id: 'media-audio',
        url: '/sound.mp3',
        preview_url: null,
        type: 'audio',
        description: 'Sound',
      },
    ]);

    expect(container.querySelector('audio')?.getAttribute('src')).toBe(
      '/sound.mp3',
    );
    expect(container.querySelector('.media-gallery--layout-1')).toBeTruthy();
  });

  it('names an attachment that is not ready to show', async () => {
    await mountWith([
      {
        id: 'media-x',
        url: null,
        preview_url: null,
        type: 'image',
        description: 'Still loading',
      },
    ]);

    expect(screen.getByText('Still loading')).toBeTruthy();
  });

  it('lets several files be picked and sends them in order', async () => {
    let uploads = 0;
    api.post.mockImplementation((url: string) => {
      if (url === '/api/v2/media') {
        uploads += 1;
        return Promise.resolve({ data: pictures[uploads - 1] });
      }
      return Promise.resolve({ data: message() });
    });
    const { container } = mountChat();
    await screen.findByText('Private message A');

    expect(
      container.querySelector('input[type="file"]')?.hasAttribute('multiple'),
    ).toBe(true);
    uploadFiles(container, 3);
    await screen.findByAltText('Picture 3');
    expect(
      screen.getAllByRole('button', { name: 'Remove attachment' }),
    ).toHaveLength(3);

    const [firstRemove] = screen.getAllByRole('button', {
      name: 'Remove attachment',
    });
    if (!firstRemove) throw new Error('Missing remove button');
    fireEvent.click(firstRemove);
    await waitFor(() => {
      expect(screen.queryByAltText('Picture 1')).toBeNull();
    });

    fireEvent.click(screen.getByRole('button', { name: 'Send' }));

    await waitFor(() => {
      expect(api.post).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/A/messages',
        { text: '', reply_to_id: null, media_ids: ['media-2', 'media-3'] },
      );
    });
  });

  it('turns away more files than the limit with a message that says so', async () => {
    const { container } = mountChat();
    await screen.findByText('Private message A');
    await waitFor(() => {
      expect(
        screen
          .getByRole('button', { name: 'Attach media' })
          .hasAttribute('disabled'),
      ).toBe(false);
    });
    api.post.mockClear();

    uploadFiles(container, 5);

    expect(await screen.findByRole('alert')).toHaveProperty(
      'textContent',
      'You can attach up to 4 files.',
    );
    expect(api.post).not.toHaveBeenCalled();
  });

  it('stops offering to attach at the limit', async () => {
    let uploads = 0;
    api.post.mockImplementation((url: string) => {
      if (url !== '/api/v2/media') return Promise.resolve({ data: {} });
      uploads += 1;
      return Promise.resolve({ data: pictures[uploads - 1] });
    });
    const { container } = mountChat();
    await screen.findByText('Private message A');
    await waitFor(() => {
      expect(
        screen
          .getByRole('button', { name: 'Attach media' })
          .hasAttribute('disabled'),
      ).toBe(false);
    });

    uploadFiles(container, 4);
    await screen.findByAltText('Picture 4');

    await waitFor(() => {
      expect(
        screen
          .getByRole('button', { name: 'Attach media' })
          .hasAttribute('disabled'),
      ).toBe(true);
    });
  });

  it('does not offer to attach when the server allows none', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/settings'
        ? Promise.resolve({ data: { ...settings, max_attachments: 0 } })
        : getResponse(url),
    );
    mountChat();
    await screen.findByText('Private message A');

    await waitFor(() => {
      expect(api.get).toHaveBeenCalledWith('/api/v1/chat/settings');
    });
    expect(
      screen
        .getByRole('button', { name: 'Attach media' })
        .hasAttribute('disabled'),
    ).toBe(true);
  });
});

describe('Chat message edits', () => {
  const mountMine = async (editable: boolean) => {
    api.get.mockImplementation((url: string) =>
      url.includes('/A/messages')
        ? Promise.resolve({ data: [{ ...message(), editable }] })
        : getResponse(url),
    );
    mountChat();
    await screen.findByText('Private message A');
  };

  it('offers to edit a message inside the edit window', async () => {
    await mountMine(true);

    expect(screen.getByRole('button', { name: 'Edit' })).toBeTruthy();
  });

  it('does not offer it once the server says the window has passed', async () => {
    await mountMine(false);

    expect(screen.queryByRole('button', { name: 'Edit' })).toBeNull();
    expect(screen.getByRole('button', { name: 'Delete' })).toBeTruthy();
  });
});

describe('Chat with a suspended account', () => {
  it('says so and does not offer to send', async () => {
    api.get.mockImplementation((url: string) =>
      url.startsWith('/api/v1/chat/conversations') && !url.includes('messages')
        ? Promise.resolve({
            data:
              url === '/api/v1/chat/conversations'
                ? [
                    {
                      ...conversation('A'),
                      accounts: [account, { ...remote, suspended: true }],
                    },
                  ]
                : {
                    ...conversation('A'),
                    accounts: [account, { ...remote, suspended: true }],
                  },
          })
        : getResponse(url),
    );
    mountChat();

    expect(await screen.findByText('This account is suspended.')).toBeTruthy();
    expect(
      screen.getByRole('button', { name: 'Send' }).hasAttribute('disabled'),
    ).toBe(true);
  });

  it('explains a message the server refuses', async () => {
    api.post.mockRejectedValue({ response: { status: 403 } });
    mountChat();
    await screen.findByText('Private message A');

    fireEvent.change(composer(), { target: { value: 'hello' } });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));

    expect(await screen.findByRole('alert')).toHaveProperty(
      'textContent',
      "This account can't receive this.",
    );
  });

  it('keeps the general message for other failures', async () => {
    mountChat();
    await screen.findByText('Private message A');
    api.post.mockRejectedValue({ response: { status: 500 } });

    fireEvent.change(composer(), { target: { value: 'hello' } });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));

    expect(await screen.findByRole('alert')).toHaveProperty(
      'textContent',
      'The chat request could not be completed.',
    );
  });
});

describe('Chat list updates', () => {
  const listRequests = () =>
    api.get.mock.calls.filter(([url]) => url === '/api/v1/chat/conversations')
      .length;
  const singleRequests = (id: string) =>
    api.get.mock.calls.filter(
      ([url]) => url === `/api/v1/chat/conversations/${id}`,
    ).length;
  const emit = async (event: string, payload: unknown) => {
    await act(async () => {
      emitChatStreamEvent({ event, payload });
      await Promise.resolve();
    });
  };
  const mountList = async () => {
    const view = mountChat('/chat');
    await screen.findByText('Room A');
    await act(async () => {
      await Promise.resolve();
    });
    api.get.mockClear();
    return view;
  };
  const rows = () =>
    Array.from(document.querySelectorAll('[data-conversation-id]')).map((row) =>
      row.getAttribute('data-conversation-id'),
    );

  it('moves a conversation to the top with its new message, without reloading the list', async () => {
    await mountList();

    await emit('chat.message', {
      ...message('B'),
      id: 'incoming',
      content: 'A new message',
      account: remote,
    });

    expect(screen.getByText('A new message')).toBeTruthy();
    expect(rows()).toEqual(['B', 'A']);
    expect(
      document.querySelector('[data-conversation-id="B"]')?.className,
    ).toContain('unread');
    expect(listRequests()).toBe(0);
    expect(singleRequests('B')).toBe(0);
  });

  it('does not mark the sender own message unread', async () => {
    await mountList();

    await emit('chat.message', { ...message('B'), id: 'own', content: 'Mine' });

    expect(screen.getByText('Mine')).toBeTruthy();
    expect(
      document.querySelector('[data-conversation-id="B"]')?.className,
    ).not.toContain('unread');
  });

  it('asks only for a conversation it does not know yet', async () => {
    await mountList();

    await emit('chat.message', {
      ...message('C'),
      id: 'first',
      account: remote,
    });

    await waitFor(() => {
      expect(screen.getByText('Room C')).toBeTruthy();
    });
    expect(singleRequests('C')).toBe(1);
    expect(listRequests()).toBe(0);
  });

  it('shows an edit of the last message without reloading', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations'
        ? Promise.resolve({
            data: [{ ...conversation('A'), last_message: message('A') }],
          })
        : getResponse(url),
    );
    await mountList();

    await emit('chat.message_update', {
      ...message('A'),
      content: 'Edited text',
    });

    expect(screen.getByText('Edited text')).toBeTruthy();
    expect(listRequests()).toBe(0);
  });

  it('asks for the conversation when an update comes without its details', async () => {
    await mountList();

    await emit('chat.conversation_update', { id: 'A' });

    await waitFor(() => {
      expect(singleRequests('A')).toBe(1);
    });
    expect(listRequests()).toBe(0);
  });

  it('applies a conversation update from its payload', async () => {
    await mountList();

    await emit('chat.conversation_update', {
      ...conversation('A'),
      title: 'Renamed',
    });

    expect(screen.getByText('Renamed')).toBeTruthy();
    expect(listRequests()).toBe(0);
    expect(singleRequests('A')).toBe(0);
  });

  it.each(['chat.member_join', 'chat.member_leave'])(
    'asks only for the conversation on %s',
    async (event) => {
      await mountList();

      await emit(event, { conversation_id: 'A', account_id: 'remote' });

      await waitFor(() => {
        expect(singleRequests('A')).toBe(1);
      });
      expect(listRequests()).toBe(0);
    },
  );

  it('asks only for the conversation when a message is hidden', async () => {
    await mountList();

    await emit('chat.message_hide', { id: 'message-A', conversation_id: 'A' });

    await waitFor(() => {
      expect(singleRequests('A')).toBe(1);
    });
    expect(listRequests()).toBe(0);
  });

  it('asks once for bursts of events about one conversation', async () => {
    const pending = deferred<{ data: ReturnType<typeof conversation> }>();
    await mountList();
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations/A'
        ? pending.promise
        : getResponse(url),
    );

    await emit('chat.member_join', { conversation_id: 'A', account_id: 'x' });
    await emit('chat.member_join', { conversation_id: 'A', account_id: 'y' });
    await emit('chat.member_leave', { conversation_id: 'A', account_id: 'z' });

    expect(singleRequests('A')).toBe(1);

    await act(async () => {
      pending.resolve({ data: conversation('A') });
      await pending.promise;
    });
    await waitFor(() => {
      expect(singleRequests('A')).toBe(2);
    });
  });

  it('drops a conversation it can no longer see', async () => {
    await mountList();
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations/A'
        ? Promise.reject(
            Object.assign(new Error('gone'), { response: { status: 404 } }),
          )
        : getResponse(url),
    );

    await emit('chat.member_leave', { conversation_id: 'A', account_id: 'me' });

    await waitFor(() => {
      expect(screen.queryByText('Room A')).toBeNull();
    });
  });

  it('does not reload the list for an invitation', async () => {
    await mountList();

    await emit('chat.invitation', { id: 'invitation' });

    expect(listRequests()).toBe(0);
    expect(api.get).toHaveBeenCalledWith('/api/v1/chat/invitations');
  });

  it('marks a message read in the open room without reloading', async () => {
    mountChat();
    await screen.findByText('Private message A');
    await act(async () => {
      await Promise.resolve();
    });
    api.get.mockClear();

    await emit('chat.message', {
      ...message('A'),
      id: 'incoming',
      account: remote,
    });
    await act(async () => {
      await Promise.resolve();
    });

    expect(listRequests()).toBe(0);
  });

  it('still reloads everything after the stream reconnects', async () => {
    await mountList();

    await emit(CHAT_STREAM_RECONNECTED, {});

    await waitFor(() => {
      expect(listRequests()).toBe(1);
    });
  });
});

describe('A failed action in a room', () => {
  it('shows in the composer, which stays on screen wherever the room is scrolled', async () => {
    api.delete.mockRejectedValue(new Error('no'));
    const { container } = mountChat();
    await screen.findByText('Private message A');

    fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
    await confirmModal();

    const alert = await screen.findByRole('alert');
    expect(
      container.querySelector('.chat-native__composer')?.contains(alert),
    ).toBe(true);
    expect(screen.getByText('Private message A')).toBeTruthy();
  });

  it('stays out of a composer on a screen that has none', async () => {
    api.delete.mockRejectedValue(new Error('no'));
    api.post.mockRejectedValue(new Error('no'));
    const { container } = mountChat('/chat/new');
    fireEvent.click(
      await screen.findByRole('button', { name: 'Create a group' }),
    );
    fireEvent.change(screen.getByPlaceholderText('Group name'), {
      target: { value: 'Room' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Create' }));

    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(container.querySelector('.chat-native__composer')).toBeNull();
  });
});

describe('Archiving a group', () => {
  const group = (extra: object = {}) => ({
    ...conversation('A'),
    type: 'group',
    title: 'Hikers',
    current_role: 'owner',
    ...extra,
  });
  const respond = (item: object) => {
    api.get.mockImplementation((url: string) => {
      if (url === '/api/v1/chat/conversations')
        return Promise.resolve({ data: [item], headers: {} });
      if (url === '/api/v1/chat/conversations/A')
        return Promise.resolve({ data: item });
      return getResponse(url);
    });
    api.post.mockResolvedValue({ data: item });
  };
  const archivePosts = () =>
    api.post.mock.calls.filter(
      ([url]) => url === '/api/v1/chat/conversations/A/archive',
    ).length;

  it('asks first, saying what happens and how to undo it', async () => {
    respond(group());
    mountChat();
    await screen.findByText('Private message A');
    dispatch.mockClear();

    fireEvent.click(screen.getByRole('button', { name: 'Archive' }));

    expect(archivePosts()).toBe(0);
    const modal = lastConfirmation();
    expect(modal?.message).toContain('nobody can send');
    expect(modal?.message).toContain('Reopen');
  });

  it('archives once confirmed', async () => {
    respond(group());
    mountChat();
    await screen.findByText('Private message A');
    dispatch.mockClear();

    fireEvent.click(screen.getByRole('button', { name: 'Archive' }));
    await confirmModal();

    await waitFor(() => {
      expect(archivePosts()).toBe(1);
    });
  });

  it('reopens from the menu without asking, since nothing is lost', async () => {
    respond(group({ archived: true }));
    mountChat();
    await screen.findByText('Private message A');
    dispatch.mockClear();

    fireEvent.click(
      within(screen.getByRole('banner')).getByRole('button', {
        name: 'Reopen',
      }),
    );

    await waitFor(() => {
      expect(api.post).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/A/unarchive',
      );
    });
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('offers the owner a way back right where the room says it is archived', async () => {
    respond(group({ archived: true }));
    const { container } = mountChat();
    const notice = (await screen.findByText('This group is archived.')).closest(
      '.chat-native__notice',
    ) as HTMLElement;

    fireEvent.click(within(notice).getByRole('button', { name: 'Reopen' }));

    await waitFor(() => {
      expect(api.post).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/A/unarchive',
      );
    });
    expect(container.querySelector('.chat-native__composer')).toBeTruthy();
  });

  it('offers a member who cannot reopen it nothing to press', async () => {
    respond(group({ archived: true, current_role: 'member' }));
    mountChat();
    const notice = (await screen.findByText('This group is archived.')).closest(
      '.chat-native__notice',
    ) as HTMLElement;

    expect(within(notice).queryByRole('button')).toBeNull();
  });

  it('marks an archived group in the list, and only that one', async () => {
    api.get.mockImplementation((url: string) =>
      url === '/api/v1/chat/conversations'
        ? Promise.resolve({
            data: [
              group({ id: 'A', title: 'Hikers', archived: true }),
              group({ id: 'B', title: 'Readers' }),
            ],
            headers: {},
          })
        : getResponse(url),
    );
    mountChat('/chat');

    const archived = (await screen.findByText('Hikers')).closest('button');
    const open = screen.getByText('Readers').closest('button');

    expect(archived?.textContent).toContain('Archived');
    expect(open?.textContent).not.toContain('Archived');
  });
});

describe('Searching for an account', () => {
  const deferredSearch = () => {
    let settle: (accounts: unknown[] | Error) => void = () => undefined;
    api.get.mockImplementation((url: string) =>
      url === '/api/v2/search'
        ? new Promise((resolve, reject) => {
            settle = (result) => {
              if (result instanceof Error) reject(result);
              else resolve({ data: { accounts: result } });
            };
          })
        : getResponse(url),
    );
    return (result: unknown[] | Error) => {
      settle(result);
    };
  };
  const type = async (value: string) => {
    fireEvent.change(
      await screen.findByPlaceholderText('Search for an account'),
      { target: { value } },
    );
  };
  const searchRequests = () =>
    api.get.mock.calls.filter(([url]) => url === '/api/v2/search').length;

  it('says it is searching from the first keystroke, before any request', async () => {
    deferredSearch();
    mountChat('/chat/new');
    await type('bob');

    expect(screen.getByRole('status').textContent).toBe('Searching…');
    expect(searchRequests()).toBe(0);
  });

  it('stops saying so when results arrive', async () => {
    const settle = deferredSearch();
    mountChat('/chat/new');
    await type('bob');
    await waitFor(() => {
      expect(searchRequests()).toBe(1);
    });
    expect(screen.getByRole('status')).toBeTruthy();

    act(() => {
      settle([remote]);
    });

    await screen.findByRole('button', { name: /Bob/ });
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('says when nothing was found', async () => {
    const settle = deferredSearch();
    mountChat('/chat/new');
    await type('nobody');
    await waitFor(() => {
      expect(searchRequests()).toBe(1);
    });

    act(() => {
      settle([]);
    });

    expect(await screen.findByText('No accounts found.')).toBeTruthy();
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('says when the search failed, which is not the same as finding nothing', async () => {
    const settle = deferredSearch();
    mountChat('/chat/new');
    await type('bob');
    await waitFor(() => {
      expect(searchRequests()).toBe(1);
    });

    act(() => {
      settle(new Error('no'));
    });

    expect(
      await screen.findByText('Could not search for accounts. Try again.'),
    ).toBeTruthy();
    expect(screen.queryByText('No accounts found.')).toBeNull();
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('says nothing for a query too short to search', async () => {
    deferredSearch();
    mountChat('/chat/new');
    await type('b');

    expect(screen.queryByRole('status')).toBeNull();
  });

  it('drops a pending search when the query becomes too short', async () => {
    deferredSearch();
    mountChat('/chat/new');
    await type('bob');
    await type('b');

    await act(async () => {
      await new Promise((resolve) => {
        setTimeout(resolve, 320);
      });
    });

    expect(searchRequests()).toBe(0);
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('works the same when creating a group', async () => {
    deferredSearch();
    mountChat('/chat/new');
    fireEvent.click(
      await screen.findByRole('button', { name: 'Create a group' }),
    );
    await type('bob');

    expect(screen.getByRole('status').textContent).toBe('Searching…');
  });
});
