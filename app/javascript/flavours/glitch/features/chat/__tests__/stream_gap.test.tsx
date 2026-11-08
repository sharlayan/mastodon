import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import { Map as ImmutableMap } from 'immutable';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { createMemoryHistory } from 'history';
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';

import type * as InitialState from 'flavours/glitch/initial_state';

// Only the socket and the far side of the requests are stand-ins. Each page below goes
// through the real stream client, the real API client and the real screen.
const Socket = vi.hoisted(() => {
  class FakeSocket {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;
    static all: FakeSocket[] = [];

    readyState = FakeSocket.CONNECTING;
    sent: string[] = [];
    onopen?: () => void;
    onclose?: (event: { code: number }) => void;
    onmessage?: (event: { data: string }) => void;
    onerror?: () => void;

    constructor() {
      FakeSocket.all.push(this);
    }

    send(frame: string) {
      this.sent.push(frame);
    }

    close() {
      this.readyState = FakeSocket.CLOSED;
    }

    connect() {
      this.readyState = FakeSocket.OPEN;
      this.onopen?.();
    }

    refuse() {
      this.readyState = FakeSocket.CLOSED;
      this.onclose?.({ code: 1006 });
    }

    subscribed() {
      this.onmessage?.({
        data: JSON.stringify({ stream: ['user'], event: 'subscribed' }),
      });
    }

    deliver(event: string, payload: unknown) {
      this.onmessage?.({
        data: JSON.stringify({
          stream: ['user'],
          event,
          payload: JSON.stringify(payload),
        }),
      });
    }
  }
  Object.assign(globalThis, { WebSocket: FakeSocket });
  return FakeSocket;
});

vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<typeof InitialState>()),
  me: 'me',
  getAccessToken: () => 'token',
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
  ColumnHeader: ({ title }: { title?: React.ReactNode }) => (
    <header>{title}</header>
  ),
}));
vi.mock(
  'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container',
  () => ({ default: () => null }),
);
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const PAGE = 40;
const person = (id: string, name: string) => ({
  id,
  acct: id,
  display_name: name,
  avatar: `/avatars/${id}.png`,
  avatar_static: `/avatars/${id}.png`,
});
const me = person('me', 'Alice');
const bob = person('bob', 'Bob');
const REQUEST_FAILED = 'The chat request could not be completed.';

interface Message {
  id: string;
  conversation_id: string;
  content: string;
  created_at: string;
  edited_at: null;
  deleted_at: null;
  reply_to_id: null;
  account: typeof me;
  reactions: never[];
  media_attachments: never[];
}
const message = (room: string, id: number): Message => ({
  id: String(id),
  conversation_id: room,
  content: `Message ${id}`,
  created_at: '2026-11-05T00:00:00Z',
  edited_at: null,
  deleted_at: null,
  reply_to_id: null,
  account: bob,
  reactions: [],
  media_attachments: [],
});

// A server with state: what a read answers is what was there at the moment it read,
// however late the answer gets back. Holding an answer back is what the tests vary.
const backend = {
  messages: new Map<string, Message[]>(),
  rooms: new Map<
    string,
    { unread: boolean; title: string; type?: 'direct' | 'group'; role?: string }
  >(),
  invitations: [] as { id: string; title: string }[],
  reads: [] as string[],
  marked: [] as string[],
  // Every request to mark a room read, answered or not, with when it came.
  markAttempts: [] as { room: string; at: number; messageId?: string }[],
  held: [] as { path: RegExp; until: Promise<void> }[],
  failing: [] as RegExp[],
  // Answers given once, in place of the real one, to the next request whose path matches.
  refusals: [] as {
    path: RegExp;
    status: number;
    headers?: Record<string, string>;
  }[],
  // Paths that fail for as long as they are listed here.
  down: [] as RegExp[],
};
const room = (id: string) => {
  const { title, unread, type, role } = backend.rooms.get(id) ?? {
    title: `Room ${id}`,
    unread: false,
  };
  return {
    id,
    type: type ?? 'direct',
    title,
    description: null,
    unread,
    muted: false,
    archived: false,
    current_role: role ?? 'member',
    accounts: [me, bob],
    last_message: backend.messages.get(id)?.at(-1) ?? null,
  };
};
const take = <T,>(list: T[], matches: (item: T) => boolean) => {
  const index = list.findIndex(matches);
  return index === -1 ? undefined : list.splice(index, 1)[0];
};
const refusalFor = (path: string) => {
  const refusal = take(backend.refusals, (item) => item.path.test(path));
  if (refusal)
    return HttpResponse.json(
      { error: 'refused' },
      { status: refusal.status, headers: refusal.headers },
    );
  if (backend.down.some((item) => item.test(path)))
    return HttpResponse.json({ error: 'unavailable' }, { status: 503 });
  return null;
};
const answer = (read: (url: URL, id: string) => unknown) =>
  (async ({
    request,
    params,
  }: {
    request: Request;
    params: Record<string, unknown>;
  }) => {
    const url = new URL(request.url);
    backend.reads.push(url.pathname + url.search);
    const fails = take(backend.failing, (path) => path.test(url.pathname));
    const refused = refusalFor(url.pathname);
    const body = read(url, String(params.id));
    const held = take(backend.held, ({ path }) => path.test(url.pathname));
    if (held) await held.until;
    if (refused) return refused;
    return fails
      ? HttpResponse.json({ error: 'unavailable' }, { status: 503 })
      : HttpResponse.json(body as never);
  }) as never;
const server = setupServer(
  http.get(
    '*/api/v1/chat/conversations',
    answer(() => [...backend.rooms.keys()].map(room)),
  ),
  http.get(
    '*/api/v1/chat/conversations/:id',
    answer((_, id) => room(id)),
  ),
  http.get(
    '*/api/v1/chat/conversations/:id/messages',
    answer((url, id) => {
      const before = url.searchParams.get('max_id');
      const list = (backend.messages.get(id) ?? []).filter(
        (item) => !before || Number(item.id) < Number(before),
      );
      return list.slice(-PAGE);
    }),
  ),
  http.post(
    '*/api/v1/chat/conversations/:id/messages',
    async ({ request, params }) => {
      const url = new URL(request.url);
      if (take(backend.failing, (path) => path.test(url.pathname)))
        return HttpResponse.json({ error: 'unavailable' }, { status: 503 });
      const held = take(backend.held, ({ path }) => path.test(url.pathname));
      if (held) await held.until;
      const id = String(params.id);
      const { text } = (await request.json()) as { text: string };
      const list = backend.messages.get(id) ?? [];
      const mine = {
        ...message(id, Number(list.at(-1)?.id ?? 0) + 1),
        content: text,
        account: me,
      };
      backend.messages.set(id, [...list, mine]);
      return HttpResponse.json(mine);
    },
  ),
  http.post(
    '*/api/v1/chat/conversations/:id/read',
    async ({ request, params }) => {
      const id = String(params.id);
      const url = new URL(request.url);
      const body = (await request.json().catch(() => ({}))) as {
        message_id?: string;
      } | null;
      backend.markAttempts.push({
        room: id,
        at: Date.now(),
        messageId: body?.message_id,
      });
      const refused = refusalFor(url.pathname);
      if (refused) return refused;
      backend.marked.push(id);
      const current = backend.rooms.get(id);
      if (current) backend.rooms.set(id, { ...current, unread: false });
      return HttpResponse.json({});
    },
  ),
  http.get(
    '*/api/v1/chat/invitations',
    answer((url) =>
      url.searchParams.get('direction') === 'sent'
        ? []
        : backend.invitations.map(({ id, title }) => ({
            id,
            state: 'pending',
            conversation: { ...room('invited'), id, title, type: 'group' },
            inviter: bob,
          })),
    ),
  ),
  http.get(
    '*/api/v1/chat/settings',
    answer(() => ({
      policy: 'everyone',
      allow_group_invites: true,
      notifications: true,
      max_group_members: 10,
      max_attachments: 4,
      federation_enabled: true,
      delete_window_hours: 24,
      soft_delete: false,
    })),
  ),
);

const seed = (id: string, from: number, to: number) => {
  const list = Array.from({ length: to - from + 1 }, (_, index) =>
    message(id, from + index),
  );
  backend.messages.set(id, [...(backend.messages.get(id) ?? []), ...list]);
  if (!backend.rooms.has(id))
    backend.rooms.set(id, { title: `Room ${id}`, unread: false });
  return list;
};
const holdNextAnswer = (path: RegExp) => {
  let release!: () => void;
  const until = new Promise<void>((resolve) => {
    release = resolve;
  });
  backend.held.push({ path, until });
  return async () => {
    await act(async () => {
      release();
      await until;
    });
  };
};
const MESSAGES = /\/messages$/;
const ROOMS = /\/conversations$/;
const INVITATIONS = /\/invitations$/;
const readsOf = (path: RegExp) =>
  backend.reads.filter((read) => path.test(read.split('?')[0] ?? ''));

// A page load: the connection starts, and the screen may come before or after it is up.
const loadPage = async () => {
  vi.resetModules();
  const [{ connectUserStream }, { Chat }, { IdentityContext }] =
    await Promise.all([
      import('flavours/glitch/actions/streaming'),
      import('../index'),
      import('flavours/glitch/identity_context'),
    ]);
  const state = {
    meta: ImmutableMap({ streaming_api_base_url: 'ws://localhost:4000' }),
    getIn: () => 'en',
  };
  const stream = connectUserStream() as unknown as (
    dispatch: () => Promise<void>,
    getState: () => typeof state,
  ) => () => void;
  stream(
    () => Promise.resolve(),
    () => state,
  );
  const history = createMemoryHistory();
  const open = (path: string, multiColumn = false) => {
    history.push(path);
    return render(
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
              <Chat multiColumn={multiColumn} />
            </Route>
          </Router>
        </IdentityContext.Provider>
      </IntlProvider>,
    );
  };
  return {
    history,
    open,
    socket: Socket.all.at(-1) as InstanceType<typeof Socket>,
  };
};
// The server answers a subscription only for a client that asked it to.
const connect = async (socket: InstanceType<typeof Socket>) => {
  await act(async () => {
    socket.connect();
    if (
      socket.sent.some(
        (frame) => (JSON.parse(frame) as { ack?: unknown }).ack === true,
      )
    )
      socket.subscribed();
    await Promise.resolve();
  });
};
// Up, and its subscription still on the way to the server.
const connectUnanswered = async (socket: InstanceType<typeof Socket>) => {
  await act(async () => {
    socket.connect();
    await Promise.resolve();
  });
};
const answerSubscription = async (socket: InstanceType<typeof Socket>) => {
  await act(async () => {
    socket.subscribed();
    await Promise.resolve();
  });
};
const dropConnection = async (socket: InstanceType<typeof Socket>) => {
  act(() => {
    socket.refuse();
  });
  await waitFor(() => {
    expect(Socket.all.at(-1)).not.toBe(socket);
  });
  return Socket.all.at(-1) as InstanceType<typeof Socket>;
};
const sendFromComposer = async (text: string) => {
  fireEvent.change(screen.getByRole('textbox'), { target: { value: text } });
  fireEvent.click(screen.getByRole('button', { name: 'Send' }));
  await screen.findByText(text);
  await settle();
};
const readFurtherUp = () => {
  const measure = vi
    .spyOn(Element.prototype, 'getBoundingClientRect')
    .mockReturnValue({ bottom: window.innerHeight + 5000 } as DOMRect);
  fireEvent.scroll(window);
  return () => {
    measure.mockImplementation(visibleGeometry);
    fireEvent.scroll(window);
  };
};
const visibleGeometry = function (this: Element) {
  if (this.classList.contains('chat-native__composer'))
    return { top: 500, bottom: 550 } as DOMRect;
  return { top: 100, bottom: 150 } as DOMRect;
};
const settle = async () => {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 60));
  });
};
const shown = () =>
  [...document.querySelectorAll('[id^="chat-message-"]')].map((node) =>
    node.id.replace('chat-message-', ''),
  );
const numbers = (from: number, to: number) =>
  Array.from({ length: to - from + 1 }, (_, index) => String(from + index));

// The first import of the screen transforms all of it, which can take longer than a test is
// given on a busy machine. Each test then imports it again from that work.
beforeAll(async () => {
  await import('../index');
}, 60_000);
beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  // Listening wraps the global WebSocket, and the stream client takes what it finds there.
  Object.defineProperty(globalThis, 'WebSocket', {
    value: Socket,
    configurable: true,
    writable: true,
  });
});
afterAll(() => {
  server.close();
});
beforeEach(() => {
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
    visibleGeometry,
  );
  backend.messages.clear();
  backend.rooms.clear();
  backend.invitations = [];
  backend.reads = [];
  backend.marked = [];
  backend.markAttempts = [];
  backend.held = [];
  backend.failing = [];
  backend.refusals = [];
  backend.down = [];
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('Chat when the stream connects after the screen has read', () => {
  it.each([
    ['one column', false],
    ['several columns', true],
  ])(
    'shows the messages that came in between, in %s',
    async (_, multiColumn) => {
      seed('A', 1, 2);
      const page = await loadPage();
      page.open('/chat/A', multiColumn);
      await screen.findByText('Message 2');

      seed('A', 3, 4);
      await connect(page.socket);

      await screen.findByText('Message 4');
      expect(shown()).toEqual(['1', '2', '3', '4']);
    },
  );

  it('shows them after the first attempt to connect failed', async () => {
    seed('A', 1, 2);
    const page = await loadPage();
    page.open('/chat/A');
    await screen.findByText('Message 2');

    act(() => {
      page.socket.refuse();
    });
    await waitFor(() => {
      expect(Socket.all.at(-1)).not.toBe(page.socket);
    });
    seed('A', 3, 3);
    await connect(Socket.all.at(-1) as InstanceType<typeof Socket>);

    await screen.findByText('Message 3');
    expect(shown()).toEqual(['1', '2', '3']);
  });

  it('shows the rooms and the invitations that came in between', async () => {
    seed('A', 1, 1);
    const page = await loadPage();
    page.open('/chat');
    await screen.findByText('Room A');

    seed('B', 1, 1);
    backend.invitations = [{ id: 'invite', title: 'Book club' }];
    await connect(page.socket);

    await screen.findByText('Room B');
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );
    expect(await screen.findByText('Book club')).toBeTruthy();
  });

  it('asks for nothing while the chat screen is not open', async () => {
    seed('A', 1, 1);
    const page = await loadPage();

    await connect(page.socket);
    await settle();

    expect(backend.reads).toEqual([]);
  });

  it.each([
    ['one column', false],
    ['several columns', true],
  ])(
    'reads once when the stream was up before the screen opened, in %s',
    async (_, multiColumn) => {
      seed('A', 1, 2);
      const page = await loadPage();
      await connect(page.socket);

      page.open('/chat/A', multiColumn);
      await screen.findByText('Message 2');
      await settle();

      expect(readsOf(MESSAGES)).toHaveLength(1);
      expect(readsOf(ROOMS)).toHaveLength(1);
      expect(readsOf(INVITATIONS)).toHaveLength(1);
    },
  );

  describe('while the first read is on its way', () => {
    it('shows that answer and then fills in after it', async () => {
      seed('A', 1, 2);
      const release = holdNextAnswer(MESSAGES);
      const page = await loadPage();
      page.open('/chat/A');
      await waitFor(() => {
        expect(readsOf(MESSAGES)).toHaveLength(1);
      });

      seed('A', 3, 3);
      await connect(page.socket);
      await settle();
      expect(readsOf(MESSAGES)).toHaveLength(1);

      await release();

      await screen.findByText('Message 3');
      expect(shown()).toEqual(['1', '2', '3']);
      expect(readsOf(MESSAGES)).toHaveLength(2);
    });

    it.each([
      ['messages', MESSAGES],
      ['rooms', ROOMS],
      ['invitations', INVITATIONS],
    ])(
      'still opens the room when reading the %s again fails',
      async (_, path) => {
        seed('A', 1, 2);
        backend.invitations = [{ id: 'invite', title: 'Book club' }];
        const release = holdNextAnswer(path);
        const page = await loadPage();
        page.open('/chat/A');
        await waitFor(() => {
          expect(readsOf(path)).toHaveLength(1);
        });

        backend.failing.push(path);
        await connect(page.socket);
        await release();
        await settle();
        await settle();

        expect(readsOf(path)).toHaveLength(2);
        expect(screen.getByText('Message 2')).toBeTruthy();
        expect(screen.getByText('Room A')).toBeTruthy();
        expect(
          screen.queryByText('The chat request could not be completed.'),
        ).toBeNull();
      },
    );

    it('leaves nothing out when the stream brings something newer first', async () => {
      seed('A', 1, PAGE);
      const release = holdNextAnswer(MESSAGES);
      const page = await loadPage();
      page.open('/chat/A');
      await waitFor(() => {
        expect(readsOf(MESSAGES)).toHaveLength(1);
      });

      seed('A', PAGE + 1, PAGE + 60);
      await connect(page.socket);
      const [newest] = seed('A', PAGE + 61, PAGE + 61);
      act(() => {
        page.socket.deliver('chat.message', newest);
      });
      await release();

      await screen.findByText('Message 1');
      await waitFor(() => {
        expect(shown()).toEqual(numbers(1, PAGE + 61));
      });
    });

    it('fills the gap after an initially empty answer when a newer stream message appears first', async () => {
      seed('A', 1, 0);
      const release = holdNextAnswer(MESSAGES);
      const page = await loadPage();
      page.open('/chat/A');
      await waitFor(() => {
        expect(readsOf(MESSAGES)).toHaveLength(1);
      });

      seed('A', 1, PAGE + 2);
      await connect(page.socket);
      const [newest] = seed('A', PAGE + 3, PAGE + 3);
      act(() => {
        page.socket.deliver('chat.message', newest);
      });
      await screen.findByText(`Message ${PAGE + 3}`);
      await release();

      await waitFor(() => {
        expect(shown()).toEqual(numbers(1, PAGE + 3));
      });
    });

    it('reads nothing more for a room that was left, and does not mark it read', async () => {
      seed('A', 1, 2);
      seed('B', 1, 1);
      const release = holdNextAnswer(MESSAGES);
      const page = await loadPage();
      page.open('/chat/A');
      await waitFor(() => {
        expect(readsOf(MESSAGES)).toHaveLength(1);
      });
      await connect(page.socket);

      act(() => {
        page.history.push('/chat/B');
      });
      await screen.findByText('Message 1');
      await release();
      await settle();

      expect(
        backend.reads.filter((read) => read.includes('/A/messages')),
      ).toHaveLength(1);
      expect(backend.marked).not.toContain('A');
    });
  });

  describe('while the stream delivers during the read after it', () => {
    const openRead = async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText('Message 2');
      seed('A', 3, 4);
      const release = holdNextAnswer(MESSAGES);
      await connect(page.socket);
      await waitFor(() => {
        expect(readsOf(MESSAGES)).toHaveLength(2);
      });
      return { page, release };
    };

    it('does not repeat a message that was also in the answer', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText('Message 2');
      const [third] = seed('A', 3, 3);
      const release = holdNextAnswer(MESSAGES);
      await connect(page.socket);
      await waitFor(() => {
        expect(readsOf(MESSAGES)).toHaveLength(2);
      });

      act(() => {
        page.socket.deliver('chat.message', third);
      });
      await release();
      await settle();

      expect(shown()).toEqual(['1', '2', '3']);
    });

    it('keeps a message the answer was too early for, after the rest', async () => {
      const { page, release } = await openRead();

      const [fifth] = seed('A', 5, 5);
      act(() => {
        page.socket.deliver('chat.message', fifth);
      });
      await release();
      await settle();

      expect(shown()).toEqual(['1', '2', '3', '4', '5']);
    });

    it('keeps a room up to date that the stream changed meanwhile', async () => {
      seed('A', 1, 1);
      const page = await loadPage();
      page.open('/chat');
      await screen.findByText('Message 1');
      const release = holdNextAnswer(ROOMS);
      await connect(page.socket);
      await waitFor(() => {
        expect(readsOf(ROOMS)).toHaveLength(2);
      });

      const [newer] = seed('A', 2, 2);
      act(() => {
        page.socket.deliver('chat.message', newer);
      });
      await release();
      await settle();

      expect(screen.getByText('Message 2')).toBeTruthy();
      expect(screen.queryByText('Message 1')).toBeNull();
      expect(screen.getByLabelText('Unread messages')).toBeTruthy();
    });
  });

  describe('while someone is reading further up', () => {
    it('adds below them without moving them, and tells them', async () => {
      const scrollIntoView = vi.fn();
      Element.prototype.scrollIntoView = scrollIntoView;
      seed('A', 1, PAGE + 10);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText(`Message ${PAGE + 10}`);
      fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
      await screen.findByText('Message 1');
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
        bottom: window.innerHeight + 5000,
      } as DOMRect);
      fireEvent.scroll(window);
      scrollIntoView.mockClear();

      seed('A', PAGE + 11, PAGE + 11);
      await connect(page.socket);

      await screen.findByText(`Message ${PAGE + 11}`);
      expect(shown()).toEqual(numbers(1, PAGE + 11));
      expect(scrollIntoView).not.toHaveBeenCalled();
      expect(screen.getByText('New messages')).toBeTruthy();
      expect(backend.marked.filter((id) => id === 'A')).toHaveLength(1);
    });
  });

  describe('until the server says the subscription is up', () => {
    it('asks only for the user stream to be answered', async () => {
      const page = await loadPage();

      await connectUnanswered(page.socket);

      expect(page.socket.sent).toEqual([
        JSON.stringify({ type: 'subscribe', stream: 'user', ack: true }),
      ]);
    });

    it('waits for that answer before reading again', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText('Message 2');

      seed('A', 3, 3);
      await connectUnanswered(page.socket);
      await settle();
      expect(readsOf(MESSAGES)).toHaveLength(1);

      // Too late for the stream, and read because the answer only comes after it.
      seed('A', 4, 4);
      await answerSubscription(page.socket);

      await screen.findByText('Message 4');
      expect(shown()).toEqual(['1', '2', '3', '4']);
      expect(readsOf(MESSAGES)).toHaveLength(2);
    });

    it('waits for it on a connection that came back as well', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText('Message 2');
      await connect(page.socket);
      await settle();
      const readsBefore = readsOf(MESSAGES).length;

      const next = await dropConnection(page.socket);
      seed('A', 3, 3);
      await connectUnanswered(next);
      await settle();
      expect(readsOf(MESSAGES)).toHaveLength(readsBefore);

      seed('A', 4, 4);
      await answerSubscription(next);

      await screen.findByText('Message 4');
      expect(shown()).toEqual(['1', '2', '3', '4']);
    });

    it('reads once however many rooms and invitations there are to read', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText('Message 2');

      await connect(page.socket);
      await settle();

      expect(readsOf(MESSAGES)).toHaveLength(2);
      expect(readsOf(ROOMS)).toHaveLength(2);
      expect(readsOf(INVITATIONS)).toHaveLength(2);
    });
  });

  describe('when the reader sends something before the stream is up', () => {
    it('leaves no hole behind their own message on the first connection', async () => {
      seed('A', 1, PAGE);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText(`Message ${PAGE}`);
      await settle();

      seed('A', PAGE + 1, PAGE + 50);
      await sendFromComposer('Mine');
      await connect(page.socket);

      await screen.findByText(`Message ${PAGE + 1}`);
      await waitFor(() => {
        expect(shown()).toEqual(numbers(1, PAGE + 51));
      });
    });

    it('leaves no hole behind their own message on a connection that came back', async () => {
      seed('A', 1, PAGE);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText(`Message ${PAGE}`);

      const next = await dropConnection(page.socket);
      seed('A', PAGE + 1, PAGE + 50);
      await sendFromComposer('Mine');
      await connect(next);

      await screen.findByText(`Message ${PAGE + 1}`);
      await waitFor(() => {
        expect(shown()).toEqual(numbers(1, PAGE + 51));
      });
    });

    it('does not take what the stream brings before its answer as all there was', async () => {
      seed('A', 1, PAGE);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText(`Message ${PAGE}`);
      await settle();

      seed('A', PAGE + 1, PAGE + 50);
      await connectUnanswered(page.socket);
      const [newest] = seed('A', PAGE + 51, PAGE + 51);
      act(() => {
        page.socket.deliver('chat.message', newest);
      });
      await settle();
      await answerSubscription(page.socket);

      await screen.findByText(`Message ${PAGE + 1}`);
      await waitFor(() => {
        expect(shown()).toEqual(numbers(1, PAGE + 51));
      });
    });
  });

  describe('when the connection comes back after the stream delivered', () => {
    it('refreshes the whole loaded history when the connection comes back', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 2');
      const delivered = seed('A', 3, PAGE + 10);
      act(() => {
        delivered.forEach((item) => {
          page.socket.deliver('chat.message', item);
        });
      });
      await screen.findByText(`Message ${PAGE + 10}`);
      backend.reads = [];

      const next = await dropConnection(page.socket);
      await connect(next);
      await settle();

      expect(readsOf(MESSAGES)).toHaveLength(2);
      expect(shown()).toEqual(numbers(1, PAGE + 10));
    });

    it('does not count on the stream while what it follows on from has not been read', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 2');
      await settle();

      const second = await dropConnection(page.socket);
      seed('A', 3, PAGE + 10);
      backend.failing.push(MESSAGES);
      await connect(second);
      await settle();
      const [newest] = seed('A', PAGE + 11, PAGE + 11);
      act(() => {
        second.deliver('chat.message', newest);
      });
      await screen.findByText(`Message ${PAGE + 11}`);
      await settle();

      const third = await dropConnection(second);
      await connect(third);

      await screen.findByText('Message 3');
      await waitFor(() => {
        expect(shown()).toEqual(numbers(1, PAGE + 11));
      });
    });

    it('counts from there when more than a page came after it', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 2');
      const [third] = seed('A', 3, 3);
      act(() => {
        page.socket.deliver('chat.message', third);
      });
      await screen.findByText('Message 3');
      await settle();

      const next = await dropConnection(page.socket);
      seed('A', 4, PAGE + 20);
      await connect(next);

      await screen.findByText(`Message ${PAGE + 20}`);
      await waitFor(() => {
        expect(shown()).toEqual(numbers(1, PAGE + 20));
      });
    });
  });

  describe('when a read failed on opening', () => {
    it.each([
      ['messages', MESSAGES],
      ['rooms', ROOMS],
      ['invitations', INVITATIONS],
    ])('stops saying so once the %s have been read', async (_, path) => {
      seed('A', 1, 2);
      backend.failing.push(path);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText(REQUEST_FAILED);

      await connect(page.socket);

      await screen.findByText('Message 2');
      await waitFor(() => {
        expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
      });
    });

    it('keeps saying so while another of those reads has not come back well', async () => {
      seed('A', 1, 2);
      backend.failing.push(MESSAGES, ROOMS);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText(REQUEST_FAILED);

      backend.failing.push(ROOMS);
      await connect(page.socket);
      await screen.findByText('Message 2');
      await settle();

      expect(screen.getByText(REQUEST_FAILED)).toBeTruthy();
    });

    it('keeps saying so when coming back reads again only other things', async () => {
      seed('A', 1, 2);
      backend.failing.push(/\/settings$/);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText(REQUEST_FAILED);

      await connect(page.socket);
      await settle();

      expect(screen.getByText(REQUEST_FAILED)).toBeTruthy();
    });

    it('does not take back a failure that reading again has nothing to do with', async () => {
      seed('A', 1, 2);
      backend.failing.push(MESSAGES);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText(REQUEST_FAILED);

      backend.failing.push(/\/messages$/);
      fireEvent.change(screen.getByRole('textbox'), {
        target: { value: 'Going out' },
      });
      fireEvent.click(screen.getByRole('button', { name: 'Send' }));
      await waitFor(() => {
        expect(backend.failing).toHaveLength(0);
      });
      await settle();
      await connect(page.socket);
      await screen.findByText('Message 2');
      await settle();

      expect(screen.getByText(REQUEST_FAILED)).toBeTruthy();
    });
  });

  describe('when a message arrives while the reader is further up', () => {
    const openFurtherUp = async () => {
      seed('A', 1, 5);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 5');
      await settle();
      const back = readFurtherUp();
      backend.marked = [];
      return { page, back };
    };
    const deliverNext = async (page: {
      socket: InstanceType<typeof Socket>;
    }) => {
      const [newer] = seed('A', 6, 6);
      act(() => {
        page.socket.deliver('chat.message', newer);
      });
      await screen.findByText('Message 6');
      await settle();
    };

    it('leaves it unread', async () => {
      const { page } = await openFurtherUp();

      await deliverNext(page);

      expect(backend.marked).toEqual([]);
      expect(screen.getByText('New messages')).toBeTruthy();
    });

    it('marks it read once the reader is back at the bottom', async () => {
      const { page, back } = await openFurtherUp();
      await deliverNext(page);

      back();

      await waitFor(() => {
        expect(backend.marked).toEqual(['A']);
      });
    });

    it('marks it read when the reader jumps to it', async () => {
      const { page } = await openFurtherUp();
      await deliverNext(page);

      // The click scrolls the real viewport; jsdom needs its resulting geometry.
      Element.prototype.scrollIntoView = vi.fn(() => {
        vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
          visibleGeometry,
        );
      });
      fireEvent.click(screen.getByText('New messages'));

      await waitFor(() => {
        expect(backend.marked).toEqual(['A']);
      });
      Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
    });

    it('marks nothing read for coming back down when nothing new came', async () => {
      const { back } = await openFurtherUp();

      back();
      await settle();

      expect(backend.marked).toEqual([]);
    });

    it('leaves it unread when the reader only comes back to the tab', async () => {
      const { page } = await openFurtherUp();
      await deliverNext(page);

      act(() => {
        document.dispatchEvent(new Event('visibilitychange'));
      });
      await settle();

      expect(backend.marked).toEqual([]);
    });

    it('still marks it read for someone at the bottom', async () => {
      seed('A', 1, 5);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 5');
      await settle();
      backend.marked = [];

      await deliverNext(page);

      expect(backend.marked).toEqual(['A']);
    });

    it('marks what reading again found read once the reader is back at the bottom', async () => {
      const { page, back } = await openFurtherUp();

      const next = await dropConnection(page.socket);
      seed('A', 6, 6);
      await connect(next);
      await screen.findByText('Message 6');
      await settle();
      expect(backend.marked).toEqual([]);

      back();

      await waitFor(() => {
        expect(backend.marked).toEqual(['A']);
      });
    });
  });

  describe('after moving to another room', () => {
    it('misses nothing when the stream was already up', async () => {
      seed('A', 1, 1);
      seed('B', 11, 12);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 1');

      const release = holdNextAnswer(MESSAGES);
      act(() => {
        page.history.push('/chat/B');
      });
      await waitFor(() => {
        expect(readsOf(MESSAGES)).toHaveLength(2);
      });
      const [newer] = seed('B', 13, 13);
      act(() => {
        page.socket.deliver('chat.message', newer);
      });
      await release();
      await settle();

      expect(shown()).toEqual(['11', '12', '13']);
      expect(readsOf(MESSAGES)).toHaveLength(2);
    });

    it('fills in the room now open, not the one left', async () => {
      seed('A', 1, 1);
      seed('B', 11, 12);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText('Message 1');

      act(() => {
        page.history.push('/chat/B');
      });
      await screen.findByText('Message 12');
      expect(shown()).toEqual(['11', '12']);

      seed('A', 2, 2);
      seed('B', 13, 13);
      await connect(page.socket);

      await screen.findByText('Message 13');
      expect(shown()).toEqual(['11', '12', '13']);
      expect(
        backend.reads.filter((read) => read.includes('/A/messages')),
      ).toHaveLength(1);
    });

    it('does not mark the room left as read when a read comes back late', async () => {
      seed('A', 1, 2);
      seed('B', 11, 11);
      const page = await loadPage();
      page.open('/chat/A');
      await screen.findByText('Message 2');
      const release = holdNextAnswer(MESSAGES);
      seed('A', 3, 3);
      await connect(page.socket);
      await waitFor(() => {
        expect(readsOf(MESSAGES)).toHaveLength(2);
      });
      backend.marked = [];

      act(() => {
        page.history.push('/chat/B');
      });
      await screen.findByText('Message 11');
      await release();
      await settle();

      expect(backend.marked).not.toContain('A');
    });
  });
});

// What the screen asks for by itself is asked for again by the screen. It cannot wait for
// the stream to say so: the stream may have been up, and said so, before the screen was there.
describe('Chat when something it asked for by itself fails', () => {
  const READ = /\/read$/;
  const SETTINGS = /\/settings$/;
  const marksOf = (id: string) =>
    backend.markAttempts.filter((mark) => mark.room === id);
  const later = async (ms: number) => {
    await act(async () => {
      await vi.advanceTimersByTimeAsync(ms);
    });
  };
  const setHidden = (hidden: boolean) => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => (hidden ? 'hidden' : 'visible'),
    });
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
  };
  // A room with something unread, opened once the stream is up.
  const openUnread = async () => {
    seed('A', 1, 2);
    backend.rooms.set('A', { title: 'Room A', unread: true });
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await waitFor(() => {
      expect(marksOf('A')).toHaveLength(1);
    });
    return page;
  };
  const listSaysUnread = async (page: Awaited<ReturnType<typeof loadPage>>) => {
    act(() => {
      page.history.push('/chat');
    });
    const item = await waitFor(() => {
      const found = document.querySelector('[data-conversation-id="A"]');
      expect(found).not.toBeNull();
      return found as HTMLElement;
    });
    await settle();
    return item.classList.contains('unread');
  };

  beforeEach(() => {
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
    Reflect.deleteProperty(document, 'visibilityState');
  });

  describe('marking the room read', () => {
    it('does not say that a request failed', async () => {
      backend.refusals.push({ path: READ, status: 503 });
      await openUnread();
      await settle();

      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    });

    it('tries again by itself, and the room is then read', async () => {
      backend.refusals.push({ path: READ, status: 503 });
      const page = await openUnread();

      await later(3_000);

      expect(backend.marked).toEqual(['A']);
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
      expect(await listSaysUnread(page)).toBe(false);
    });

    it('waits as long as the server says after too many requests', async () => {
      backend.refusals.push({
        path: READ,
        status: 429,
        headers: {
          'X-RateLimit-Reset': new Date(Date.now() + 20_000).toISOString(),
        },
      });
      await openUnread();

      await later(15_000);
      expect(marksOf('A')).toHaveLength(1);

      await later(6_000);
      expect(backend.marked).toEqual(['A']);
    });

    it('tries a few times, further apart each time, and then leaves it for the next time', async () => {
      backend.down.push(READ);
      const page = await openUnread();

      await later(10 * 60_000);

      const marks = marksOf('A');
      const gaps = marks
        .slice(1)
        .map((mark, index) => mark.at - (marks[index]?.at ?? 0));
      expect(marks.length).toBeGreaterThan(1);
      expect(marks.length).toBeLessThanOrEqual(5);
      gaps.forEach((gap, index) => {
        expect(gap).toBeGreaterThanOrEqual(gaps[index - 1] ?? 1_000);
      });
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
      expect(await listSaysUnread(page)).toBe(true);
    });

    it('stops once the reader has left the room', async () => {
      backend.down.push(READ);
      const page = await openUnread();
      await later(3_000);
      expect(marksOf('A')).toHaveLength(2);

      act(() => {
        page.history.push('/chat');
      });
      await screen.findByText('Room A');
      await later(10 * 60_000);

      expect(marksOf('A')).toHaveLength(2);
    });

    it('stops while the page is hidden, and tries once when it is shown again', async () => {
      backend.down.push(READ);
      await openUnread();
      await later(3_000);
      expect(marksOf('A')).toHaveLength(2);

      setHidden(true);
      await later(10 * 60_000);
      expect(marksOf('A')).toHaveLength(2);

      backend.down = [];
      setHidden(false);
      await waitFor(() => {
        expect(backend.marked).toEqual(['A']);
      });
      await settle();
      expect(marksOf('A')).toHaveLength(3);
    });

    it('tries again when marking a message that came in live failed', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 2');
      await waitFor(() => {
        expect(backend.marked).toEqual(['A']);
      });
      backend.markAttempts = [];
      backend.refusals.push({ path: READ, status: 503 });

      const [newest] = seed('A', 3, 3);
      act(() => {
        page.socket.deliver('chat.message', newest);
      });
      await screen.findByText('Message 3');
      await waitFor(() => {
        expect(marksOf('A')).toHaveLength(1);
      });
      await later(3_000);

      expect(marksOf('A').map((mark) => mark.messageId)).toEqual(['3', '3']);
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    });
  });

  describe('reading what failed on opening, when the stream was up before', () => {
    it.each([
      ['messages', MESSAGES],
      ['rooms', ROOMS],
      ['invitations', INVITATIONS],
      ['settings', SETTINGS],
    ])(
      'reads the %s again by itself, and stops saying that a request failed',
      async (_, path) => {
        seed('A', 1, 2);
        const page = await loadPage();
        await connect(page.socket);
        backend.failing.push(path);
        page.open('/chat/A');
        await screen.findByText(REQUEST_FAILED);

        await later(3_000);

        await screen.findByText('Message 2');
        await waitFor(() => {
          expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
        });
      },
    );

    it('keeps saying so while the read goes on failing', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      await connect(page.socket);
      backend.down.push(SETTINGS);
      page.open('/chat/A');
      await screen.findByText(REQUEST_FAILED);

      await later(10 * 60_000);

      expect(screen.getByText(REQUEST_FAILED)).toBeTruthy();
      expect(readsOf(SETTINGS).length).toBeLessThanOrEqual(5);
    });
  });

  describe('reading again what an event asked for', () => {
    it('reads the invitations again by itself after reading them for a new one failed', async () => {
      seed('A', 1, 1);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat');
      await screen.findByText('Room A');
      await settle();

      backend.failing.push(INVITATIONS);
      backend.invitations = [{ id: 'invite', title: 'Book club' }];
      act(() => {
        page.socket.deliver('chat.invitation', { id: 'invite' });
      });
      await screen.findByText(REQUEST_FAILED);

      await later(3_000);

      await waitFor(() => {
        expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
      });
      fireEvent.click(
        await screen.findByRole('button', { name: /Invitations\s*1/ }),
      );
      expect(await screen.findByText('Book club')).toBeTruthy();
    });

    it('reads the sent invitations again by itself on the members screen', async () => {
      seed('A', 1, 1);
      backend.rooms.set('A', {
        title: 'Book club',
        unread: false,
        type: 'group',
        role: 'owner',
      });
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 1');
      await settle();

      backend.failing.push(INVITATIONS);
      act(() => {
        page.history.push('/chat/A/members');
      });
      await screen.findByText(REQUEST_FAILED);

      await later(3_000);

      await waitFor(() => {
        expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
      });
      expect(
        backend.reads.filter((read) => read.includes('direction=sent')),
      ).toHaveLength(2);
    });
  });

  describe('what the reader did', () => {
    it('keeps saying that sending failed, and does not send again by itself', async () => {
      seed('A', 1, 2);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat/A');
      await screen.findByText('Message 2');
      await settle();
      backend.failing.push(/\/messages$/);

      fireEvent.change(screen.getByRole('textbox'), {
        target: { value: 'Going out' },
      });
      fireEvent.click(screen.getByRole('button', { name: 'Send' }));
      await screen.findByText(REQUEST_FAILED);

      await later(10 * 60_000);

      expect(screen.getByText(REQUEST_FAILED)).toBeTruthy();
      expect(backend.messages.get('A')).toHaveLength(2);
    });
  });
});

describe('Independent review: overlapping failures', () => {
  beforeEach(() => {
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('preserves a user send failure after a later background read fails and recovers', async () => {
    seed('A', 1, 2);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await settle();
    backend.failing.push(/\/messages$/);
    fireEvent.change(screen.getByRole('textbox'), {
      target: { value: 'unsent text' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    await screen.findByText(REQUEST_FAILED);
    expect(backend.messages.get('A')).toHaveLength(2);
    backend.failing.push(INVITATIONS);
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'invite' });
    });
    await settle();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000);
    });
    expect(screen.getByText(REQUEST_FAILED)).toBeTruthy();
  });

  it('keeps the send failure visible while a retry has not yet succeeded', async () => {
    seed('A', 1, 2);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await settle();
    backend.failing.push(MESSAGES);
    fireEvent.change(screen.getByRole('textbox'), {
      target: { value: 'unsent text' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    await screen.findByText(REQUEST_FAILED);
    const release = holdNextAnswer(MESSAGES);
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    await settle();
    expect(screen.getByText(REQUEST_FAILED)).toBeTruthy();
    expect(backend.messages.get('A')).toHaveLength(2);
    await release();
    await screen.findByText('unsent text');
    await waitFor(() => {
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    });
  });

  it('honours the invitation endpoint 429 deadline when a second invitation event arrives', async () => {
    seed('A', 1, 2);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await settle();
    const prior = readsOf(INVITATIONS).length;
    backend.refusals.push({
      path: INVITATIONS,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'invite1' });
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS).length).toBe(prior + 1);
    });
    await settle();
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'invite2' });
    });
    await settle();
    expect(readsOf(INVITATIONS).length).toBe(prior + 1);
  });

  it('honours the invitation 429 deadline when the stream reconnects', async () => {
    seed('A', 1, 2);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await settle();
    const prior = readsOf(INVITATIONS).length;
    backend.refusals.push({
      path: INVITATIONS,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'invite1' });
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS).length).toBe(prior + 1);
    });
    const next = await dropConnection(page.socket);
    await connect(next);
    await settle();
    expect(readsOf(INVITATIONS).length).toBe(prior + 1);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(20_000);
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS).length).toBe(prior + 2);
    });
  });
});

describe('Independent review: unread arriving during read retry', () => {
  beforeEach(() => {
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
  });
  it('does not mark a message that arrived after the reader scrolled away', async () => {
    seed('A', 1, 2);
    backend.rooms.set('A', { title: 'Room A', unread: true });
    backend.refusals.push({ path: /\/read$/, status: 503 });
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await waitFor(() => {
      expect(backend.markAttempts).toHaveLength(1);
    });
    const restore = readFurtherUp();
    const [newest] = seed('A', 3, 3);
    act(() => {
      page.socket.deliver('chat.message', newest);
    });
    await screen.findByText('Message 3');
    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000);
    });
    expect(backend.markAttempts).toHaveLength(2);
    expect(backend.markAttempts[1]?.messageId).toBe('2');
    restore();
  });
});

describe('Independent review: hidden tab', () => {
  afterEach(() => {
    Reflect.deleteProperty(document, 'visibilityState');
  });
  it('does not fetch invitations for an event received while hidden', async () => {
    seed('A', 1, 2);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await settle();
    const prior = readsOf(INVITATIONS).length;
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'hidden',
    });
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'invite1' });
    });
    await settle();
    expect(readsOf(INVITATIONS).length).toBe(prior);
  });

  it('does not fetch invitations on a reconnect until the page is shown', async () => {
    seed('A', 1, 2);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await settle();
    const prior = readsOf(INVITATIONS).length;
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'hidden',
    });
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    const next = await dropConnection(page.socket);
    await connect(next);
    await settle();
    expect(readsOf(INVITATIONS).length).toBe(prior);
    Reflect.deleteProperty(document, 'visibilityState');
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS).length).toBe(prior + 1);
    });
  });
});

describe('Independent re-review: in-flight and navigation', () => {
  afterEach(() => {
    server.resetHandlers();
    Reflect.deleteProperty(document, 'visibilityState');
    vi.useRealTimers();
  });
  it('does not start a second read mark after the tab becomes hidden', async () => {
    seed('A', 1, 2);
    backend.rooms.set('A', { title: 'Room A', unread: true });
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    const sent: { id?: string; hidden: boolean }[] = [];
    server.use(
      http.post('*/api/v1/chat/conversations/:id/read', async ({ request }) => {
        const body = (await request.json()) as { message_id?: string };
        sent.push({
          id: body.message_id,
          hidden: document.visibilityState === 'hidden',
        });
        if (sent.length === 1) await held;
        return HttpResponse.json({});
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await waitFor(() => {
      expect(sent).toHaveLength(1);
    });
    const [next] = seed('A', 3, 3);
    act(() => {
      page.socket.deliver('chat.message', next);
    });
    await screen.findByText('Message 3');
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'hidden',
    });
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(sent).toEqual([{ id: '2', hidden: false }]);
    Reflect.deleteProperty(document, 'visibilityState');
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await waitFor(() => {
      expect(sent).toEqual([
        { id: '2', hidden: false },
        { id: '3', hidden: false },
      ]);
    });
  });
  it('retains an invitation 429 deadline when navigating to another room', async () => {
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
    seed('A', 1, 2);
    seed('B', 1, 2);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await settle();
    const prior = readsOf(INVITATIONS).length;
    backend.refusals.push({
      path: INVITATIONS,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'one' });
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS)).toHaveLength(prior + 1);
    });
    await settle();
    act(() => {
      page.history.push('/chat/B');
    });
    await screen.findByText('Room B');
    await settle();
    expect(readsOf(INVITATIONS)).toHaveLength(prior + 1);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(20_000);
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS)).toHaveLength(prior + 2);
    });
  });
  it('keeps unread on an old chat.read event and clears it for the last message', async () => {
    seed('A', 1, 3);
    backend.rooms.set('A', { title: 'Room A', unread: true });
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    const item = () =>
      document.querySelector('[data-conversation-id="A"]') as HTMLElement;
    await waitFor(() => {
      expect(item().classList.contains('unread')).toBe(true);
    });
    act(() => {
      page.socket.deliver('chat.read', {
        conversation_id: 'A',
        message_id: '2',
      });
    });
    await settle();
    expect(item().classList.contains('unread')).toBe(true);
    act(() => {
      page.socket.deliver('chat.read', {
        conversation_id: 'A',
        message_id: '3',
      });
    });
    await waitFor(() => {
      expect(item().classList.contains('unread')).toBe(false);
    });
  });
});

describe('Independent c5d8: late shared 429 deadline', () => {
  beforeEach(() => {
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
  });
  it('updates a new room retry timer when the departed room later reports a longer 429', async () => {
    seed('A', 1, 2);
    seed('B', 1, 2);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 2');
    await settle();
    const prior = readsOf(INVITATIONS).length;
    backend.refusals.push({
      path: INVITATIONS,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    const releaseOld = holdNextAnswer(INVITATIONS);
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'held' });
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS)).toHaveLength(prior + 1);
    });
    backend.refusals.push({ path: INVITATIONS, status: 503 });
    act(() => {
      page.history.push('/chat/B');
    });
    await screen.findByText('Room B');
    await waitFor(() => {
      expect(readsOf(INVITATIONS)).toHaveLength(prior + 2);
    });
    await screen.findByText(REQUEST_FAILED);
    await releaseOld();
    await settle();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2100);
    });
    expect(readsOf(INVITATIONS)).toHaveLength(prior + 2);
  });
});

describe('Independent 4d6a: paginated in-flight requests', () => {
  afterEach(() => {
    Reflect.deleteProperty(document, 'visibilityState');
  });
  const beginResync = async () => {
    seed('A', 1, 40);
    seed('B', 1, 2);
    const page = await loadPage();
    page.open('/chat/A');
    await screen.findByText('Message 40');
    await settle();
    seed('A', 41, 140);
    const release = holdNextAnswer(MESSAGES);
    await connect(page.socket);
    await waitFor(() => {
      expect(
        backend.reads.filter((r) => r.includes('/A/messages')),
      ).toHaveLength(2);
    });
    return { page, release };
  };
  it('starts no further message page after the tab becomes hidden', async () => {
    const { release } = await beginResync();
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'hidden',
    });
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await release();
    await settle();
    expect(backend.reads.filter((r) => r.includes('/A/messages'))).toHaveLength(
      2,
    );
    Reflect.deleteProperty(document, 'visibilityState');
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await screen.findByText('Message 140');
    expect(shown()).toEqual(numbers(1, 140));
  });
  it('starts no further message page after leaving the room', async () => {
    const { page, release } = await beginResync();
    act(() => {
      page.history.push('/chat/B');
    });
    await screen.findByText('Room B');
    await release();
    await settle();
    expect(backend.reads.filter((r) => r.includes('/A/messages'))).toHaveLength(
      2,
    );
  });
});

describe('Independent 4d6a: late 429 during paginated resync', () => {
  it('honours the late shared deadline before requesting the next message page', async () => {
    seed('A', 1, 40);
    seed('B', 1, 2);
    const page = await loadPage();
    backend.refusals.push({
      path: /\/A\/messages$/,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    const releaseOld = holdNextAnswer(/\/A\/messages$/);
    page.open('/chat/A');
    await waitFor(() => {
      expect(
        backend.reads.filter((r) => r.includes('/A/messages')),
      ).toHaveLength(1);
    });
    act(() => {
      page.history.push('/chat/B');
    });
    await screen.findByText('Room B');
    act(() => {
      page.history.push('/chat/A');
    });
    await screen.findByText('Message 40');
    await settle();
    seed('A', 41, 140);
    const releaseResync = holdNextAnswer(/\/A\/messages$/);
    await connect(page.socket);
    await waitFor(() => {
      expect(
        backend.reads.filter((r) => r.includes('/A/messages')),
      ).toHaveLength(3);
    });
    await releaseOld();
    await settle();
    await releaseResync();
    await settle();
    expect(backend.reads.filter((r) => r.includes('/A/messages'))).toHaveLength(
      3,
    );
  });
});

describe('Independent 4d6a: other sequential reads', () => {
  afterEach(() => {
    server.resetHandlers();
    Reflect.deleteProperty(document, 'visibilityState');
  });
  const hide = () => {
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'hidden',
    });
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
  };
  const show = () => {
    Reflect.deleteProperty(document, 'visibilityState');
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
  };
  it('pauses a multi-page conversation refresh until shown and keeps both pages', async () => {
    for (let n = 0; n < 22; n++) seed(`room${n}`, 1, 1);
    let hold = false;
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    server.use(
      http.get('*/api/v1/chat/conversations', async ({ request }) => {
        const url = new URL(request.url);
        backend.reads.push(url.pathname + url.search);
        const all = [...backend.rooms.keys()].map(room);
        const data = url.searchParams.has('max_id')
          ? all.slice(20)
          : all.slice(0, 20);
        if (hold && !url.searchParams.has('max_id')) await held;
        return HttpResponse.json(data);
      }),
    );
    const page = await loadPage();
    page.open('/chat');
    await screen.findByText('Room room0');
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText('Room room21');
    hold = true;
    await connect(page.socket);
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(3);
    });
    hide();
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(readsOf(ROOMS)).toHaveLength(3);
    show();
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(4);
    });
    await screen.findByText('Room room21');
    expect(document.querySelectorAll('[data-conversation-id]')).toHaveLength(
      22,
    );
  });
  it('pauses conversation pages after accepting an invitation while hidden', async () => {
    for (let n = 0; n < 22; n++) seed(`room${n}`, 1, 1);
    backend.invitations = [{ id: 'invite', title: 'Invited room' }];
    let hold = false;
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    server.use(
      http.post('*/api/v1/chat/invitations/:id/accept', () =>
        HttpResponse.json({}),
      ),
      http.get('*/api/v1/chat/conversations', async ({ request }) => {
        const url = new URL(request.url);
        backend.reads.push(url.pathname + url.search);
        const all = [...backend.rooms.keys()].map(room);
        const data = url.searchParams.has('max_id')
          ? all.slice(20)
          : all.slice(0, 20);
        if (hold && !url.searchParams.has('max_id')) await held;
        return HttpResponse.json(data);
      }),
    );
    const page = await loadPage();
    page.open('/chat');
    await screen.findByText('Room room0');
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText('Room room21');
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );
    await screen.findByText('Invited room');
    hold = true;
    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(3);
    });
    hide();
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(readsOf(ROOMS)).toHaveLength(3);
    show();
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(4);
    });
  });
  it('pauses a sent-invitations page until the members screen is visible', async () => {
    seed('A', 1, 1);
    backend.rooms.set('A', {
      title: 'Room A',
      unread: false,
      type: 'group',
      role: 'owner',
    });
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    server.use(
      http.get('*/api/v1/chat/invitations', async ({ request }) => {
        const url = new URL(request.url);
        backend.reads.push(url.pathname + url.search);
        if (url.searchParams.get('direction') !== 'sent')
          return HttpResponse.json([]);
        if (url.searchParams.has('max_id')) return HttpResponse.json([]);
        await held;
        return HttpResponse.json(
          Array.from({ length: 40 }, (_, n) => ({
            id: String(n + 1),
            state: 'pending',
            conversation: room('A'),
            inviter: me,
            invitee: bob,
          })),
        );
      }),
    );
    const page = await loadPage();
    page.open('/chat/A/members');
    await waitFor(() => {
      expect(
        backend.reads.filter((r) => r.includes('direction=sent')),
      ).toHaveLength(1);
    });
    hide();
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(
      backend.reads.filter((r) => r.includes('direction=sent')),
    ).toHaveLength(1);
    show();
    await waitFor(() => {
      expect(
        backend.reads.filter((r) => r.includes('direction=sent')),
      ).toHaveLength(2);
    });
  });
  it('pauses a coalesced conversation detail refresh while hidden', async () => {
    seed('A', 1, 1);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    await settle();
    const [first, second] = seed('B', 1, 2);
    const release = holdNextAnswer(/\/conversations\/B$/);
    act(() => {
      page.socket.deliver('chat.message', first);
    });
    await waitFor(() => {
      expect(
        backend.reads.filter((r) => r.endsWith('/conversations/B')),
      ).toHaveLength(1);
    });
    act(() => {
      page.socket.deliver('chat.message', second);
    });
    hide();
    await release();
    await settle();
    expect(
      backend.reads.filter((r) => r.endsWith('/conversations/B')),
    ).toHaveLength(1);
    show();
    await waitFor(() => {
      expect(
        backend.reads.filter((r) => r.endsWith('/conversations/B')),
      ).toHaveLength(2);
    });
  });
});
