import { useCallback } from 'react';

import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from '@testing-library/react';
import { createMemoryHistory } from 'history';

import type { ColumnHeaderProps } from 'flavours/glitch/components/column/header';
import { IdentityContext } from 'flavours/glitch/identity_context';
import type * as InitialState from 'flavours/glitch/initial_state';

import { Chat } from '../index';
import { emitChatStreamEvent } from '../stream';

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn(), patch: vi.fn() }));
vi.mock('flavours/glitch/api', () => ({ default: () => api }));
vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<typeof InitialState>()),
  me: 'me',
}));
// The surrounding column controls and global emoji picker require the app store;
// keep chat's forms, message rendering, router and stream subscriptions real.
vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: ({ title, children }: ColumnHeaderProps) => (
    <header>
      {title}
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
          <Route path='/chat/:conversationId?'>
            <Chat />
          </Route>
        </Router>
      </IdentityContext.Provider>
    </IntlProvider>,
  );
  return { ...view, history };
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
});
afterEach(cleanup);

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

describe('Chat live updates', () => {
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

  it('does not restore a reaction when its local request finishes after deletion', async () => {
    const pending = deferred<{ data: typeof reaction }>();
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
