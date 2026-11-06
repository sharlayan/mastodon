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

// Review 37ca: jsdom's multipart body does not reach MSW, so only the upload POST itself is
// answered here (as Mastodon answers a video: 202, no URL yet). Every other request, including
// the processing poll, goes through the real API client to MSW.
vi.mock('flavours/glitch/api', async (importOriginal) => {
  const actual = await importOriginal<{
    default: (auth?: boolean) => {
      post: (...args: unknown[]) => Promise<unknown>;
    };
  }>();
  return {
    ...actual,
    default: (withAuthorization?: boolean) => {
      const instance = actual.default(withAuthorization);
      const post = instance.post.bind(instance);
      instance.post = (url: unknown, ...rest: unknown[]) => {
        if (url === '/api/v2/media') {
          (globalThis as { __uploads?: number }).__uploads =
            ((globalThis as { __uploads?: number }).__uploads ?? 0) + 1;
          // Review a99b: a file whose name says "bad" is refused, as Mastodon refuses an
          // unsupported file (422). Every other file is answered as before (202, no URL yet).
          const file = (rest[0] as FormData | undefined)?.get('file') as
            | File
            | undefined;
          if (file?.name.includes('bad'))
            return Promise.reject(
              Object.assign(new Error('422'), {
                response: { status: 422, data: { error: 'refused' } },
              }),
            );
          return Promise.resolve({
            status: 202,
            data: {
              id: 'm1',
              type: 'video',
              url: null,
              preview_url: null,
              description: null,
            },
          });
        }
        return post(url, ...rest);
      };
      return instance;
    },
  };
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
// Review a99b: the room menu is drawn as plain buttons so a test can press Mute.
vi.mock('flavours/glitch/components/dropdown_menu', () => ({
  Dropdown: ({
    items,
  }: {
    items?: ({ text: string; action?: () => void } | null)[];
  }) => (
    <div data-testid='room-menu'>
      {(items ?? []).map((item) =>
        item?.action ? (
          <button
            key={item.text}
            type='button'
            data-menu-item={item.text}
            onClick={item.action}
          >
            {item.text}
          </button>
        ) : null,
      )}
    </div>
  ),
}));
// Review a99b: the header also draws its extra button, where the room menu lives.
vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: ({
    title,
    extraButton,
    children,
  }: {
    title?: React.ReactNode;
    extraButton?: React.ReactNode;
    children?: React.ReactNode;
  }) => (
    <header>
      <h1 data-testid='column-title'>{title}</h1>
      {extraButton}
      {children}
    </header>
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
const ROOMS = /\/conversations$/;
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
const dropConnection = async (socket: InstanceType<typeof Socket>) => {
  act(() => {
    socket.refuse();
  });
  await waitFor(() => {
    expect(Socket.all.at(-1)).not.toBe(socket);
  });
  return Socket.all.at(-1) as InstanceType<typeof Socket>;
};
const settle = async () => {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 60));
  });
};
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

// ---- Review 37ca: reproductions ----
const later = async (ms: number) => {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
};
const listed = () =>
  [...document.querySelectorAll('[data-conversation-id]')].map(
    (node) => (node as HTMLElement).dataset.conversationId,
  );
const INVITATIONS = /\/invitations$/;

// ---- Review a1b5: reproductions. Each test asserts what the screen should do; a failing
// assertion is a reproduced defect. What each one saw goes to mock-events.jsonl. ----
const note = vi.fn().mockResolvedValue(undefined);
const lastId = (id: string) =>
  Number(backend.messages.get(id)?.at(-1)?.id ?? 0);
// The list as the server pages it: newest last message first, and max_id is a keyset on the
// cursor room's last message as it is when the page is asked for.
const useActivityPagedRooms = () => {
  server.use(
    http.get(
      '*/api/v1/chat/conversations',
      answer((url) => {
        const maxId = url.searchParams.get('max_id');
        const order = (a: string, b: string) =>
          lastId(b) - lastId(a) || Number(b) - Number(a);
        return [...backend.rooms.keys()]
          .sort(order)
          .filter(
            (id) =>
              !maxId ||
              lastId(id) < lastId(maxId) ||
              (lastId(id) === lastId(maxId) && Number(id) < Number(maxId)),
          )
          .slice(0, 20)
          .map(room);
      }),
    ),
  );
};

describe('Review a1b5', () => {
  beforeEach(() => {
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
    server.resetHandlers();
    Reflect.deleteProperty(document, 'visibilityState');
  });

  it('N1 Load more that waited for a rate-limited list read does not skip a room', async () => {
    // Rooms 1..25, room n's last message is n: page one is 25..6, and Load more asks max_id=6.
    for (let id = 1; id <= 25; id += 1) seed(String(id), id, id);
    useActivityPagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('6');
    });
    await settle();
    const before = listed();
    // While the stream is away, room 3 (on page two) gets a message and moves to the top.
    backend.messages.set('3', [
      ...(backend.messages.get('3') ?? []),
      message('3', 100),
    ]);
    backend.refusals.push({
      path: ROOMS,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(2);
    });
    await settle();
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await later(1_000);
    const readsWhileLimited = readsOf(ROOMS).length;
    await later(20_000);
    await settle();
    await later(1_000);
    await settle();
    const after = listed();
    const serverOrder = [...backend.rooms.keys()].sort(
      (a, b) => lastId(b) - lastId(a) || Number(b) - Number(a),
    );
    await note('N1-load-more-stale-cursor', {
      before,
      readsWhileLimited,
      reads: readsOf(ROOMS).map((read) => read),
      allReads: backend.reads.filter((read) => read.includes('conversations')),
      after,
      missing: serverOrder.filter((id) => !after.includes(id)),
      loadMoreButton: Boolean(
        screen.queryByRole('button', { name: 'Load more' }),
      ),
      notice: Boolean(screen.queryByText(REQUEST_FAILED)),
    });
    expect(readsWhileLimited).toBe(2);
    expect(after).toContain('6');
    expect(new Set(after).size).toBe(after.length);
    expect(after).toEqual(serverOrder);
  }, 60_000);

  it('N2 a detail read answered before Mute does not undo Mute when it arrives late', async () => {
    seed('A', 1, 1);
    backend.rooms.set('A', {
      title: 'Room A',
      unread: false,
      type: 'group',
      role: 'owner',
    });
    const muted = new Set<string>();
    const withMute = (id: string) => ({ ...room(id), muted: muted.has(id) });
    server.use(
      http.get(
        '*/api/v1/chat/conversations',
        answer(() => [...backend.rooms.keys()].map(withMute)),
      ),
      http.get(
        '*/api/v1/chat/conversations/:id',
        answer((_, id) => withMute(id)),
      ),
      // Mastodon answers mute with render_empty ({}), and sends no stream event.
      http.post('*/api/v1/chat/conversations/:id/mute', ({ params }) => {
        muted.add(String(params.id));
        backend.reads.push('POST mute');
        return HttpResponse.json({});
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 1');
    await screen.findByRole('button', { name: 'Mute' });
    await settle();
    const DETAIL = /\/conversations\/A$/;
    const release = holdNextAnswer(DETAIL);
    // Someone joins: the screen reads the room again. The server answers now (not muted).
    act(() => {
      page.socket.deliver('chat.member_join', {
        conversation_id: 'A',
        account_id: 'carol',
      });
    });
    await waitFor(() => {
      expect(readsOf(DETAIL)).toHaveLength(1);
    });
    const roomReadsBefore = readsOf(ROOMS).length;
    fireEvent.click(screen.getByRole('button', { name: 'Mute' }));
    await screen.findByRole('button', { name: 'Unmute' });
    await waitFor(() => {
      expect(readsOf(ROOMS).length).toBe(roomReadsBefore + 1);
    });
    await settle();
    const afterListRead = {
      unmute: Boolean(screen.queryByRole('button', { name: 'Unmute' })),
    };
    await release();
    await settle();
    await later(30_000);
    await settle();
    const state = {
      mute: Boolean(screen.queryByRole('button', { name: 'Mute' })),
      unmute: Boolean(screen.queryByRole('button', { name: 'Unmute' })),
      serverMuted: muted.has('A'),
      readsAfter: backend.reads.slice(-6),
    };
    await note('N2-late-detail-undoes-mute', { afterListRead, state });
    expect(state.serverMuted).toBe(true);
    expect(state.unmute).toBe(true);
  }, 60_000);

  it('N3a a message hidden for me leaves the search results', async () => {
    seed('A', 1, 1);
    const found = {
      ...message('A', 1),
      account: me,
      content: 'A unique search result',
    };
    server.use(
      http.get('*/api/v1/chat/messages/search', () =>
        HttpResponse.json([found]),
      ),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    fireEvent.click(screen.getByRole('button', { name: 'Search messages' }));
    fireEvent.change(screen.getByPlaceholderText('Search messages'), {
      target: { value: 'unique' },
    });
    await later(1_000);
    await screen.findByText('A unique search result');
    act(() => {
      page.socket.deliver('chat.message_hide', {
        id: '1',
        conversation_id: 'A',
      });
    });
    await settle();
    const shown = Boolean(screen.queryByText('A unique search result'));
    await note('N3a-hide-shown-results', { shownAfterHide: shown });
    expect(shown).toBe(false);
  });

  it('N3b a search answer that left before a hide does not bring the hidden message back', async () => {
    seed('A', 1, 1);
    const found = {
      ...message('A', 1),
      account: me,
      content: 'A unique search result',
    };
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    let asked = false;
    server.use(
      http.get('*/api/v1/chat/messages/search', async () => {
        asked = true;
        await held;
        return HttpResponse.json([found]);
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    fireEvent.click(screen.getByRole('button', { name: 'Search messages' }));
    fireEvent.change(screen.getByPlaceholderText('Search messages'), {
      target: { value: 'unique' },
    });
    await later(1_000);
    await waitFor(() => {
      expect(asked).toBe(true);
    });
    act(() => {
      page.socket.deliver('chat.message_hide', {
        id: '1',
        conversation_id: 'A',
      });
    });
    await act(async () => {
      release();
      await held;
    });
    await settle();
    const shown = Boolean(screen.queryByText('A unique search result'));
    await note('N3b-hide-late-search', { shownAfterLateAnswer: shown });
    expect(shown).toBe(false);
  });

  it('N3c (consequence) opening a hidden search result reads the whole room looking for it', async () => {
    seed('A', 1, 200);
    const target = {
      ...message('A', 5),
      account: me,
      content: 'A unique search result',
    };
    // The server no longer gives the author a message they hid.
    backend.messages.set(
      'A',
      (backend.messages.get('A') ?? []).filter((item) => item.id !== '5'),
    );
    server.use(
      http.get('*/api/v1/chat/messages/search', () =>
        HttpResponse.json([target]),
      ),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    fireEvent.click(screen.getByRole('button', { name: 'Search messages' }));
    fireEvent.change(screen.getByPlaceholderText('Search messages'), {
      target: { value: 'unique' },
    });
    await later(1_000);
    await screen.findByText('A unique search result');
    act(() => {
      page.socket.deliver('chat.message_hide', {
        id: '5',
        conversation_id: 'A',
      });
    });
    await settle();
    const stillShown = Boolean(screen.queryByText('A unique search result'));
    if (stillShown) {
      fireEvent.click(
        document.querySelector(
          '.chat-native__search-results button',
        ) as HTMLElement,
      );
      await screen.findByText('Message 200');
      await later(3_000);
      await settle();
    }
    const MESSAGES = /\/conversations\/A\/messages$/;
    await note('N3c-hidden-result-jump', {
      stillShown,
      messageReads: readsOf(MESSAGES),
    });
    expect(stillShown).toBe(false);
  }, 30_000);

  it('N4 a sent invitation shows on the members screen without waiting out a sent-list deadline', async () => {
    seed('A', 1, 1);
    backend.rooms.set('A', {
      title: 'Room A',
      unread: false,
      type: 'group',
      role: 'owner',
    });
    const carol = person('carol', 'Carol');
    let sent: unknown[] = [];
    let sentReads = 0;
    server.use(
      http.get('*/api/v1/chat/invitations', ({ request }) => {
        const url = new URL(request.url);
        if (url.searchParams.get('direction') !== 'sent')
          return HttpResponse.json([]);
        sentReads += 1;
        backend.reads.push(`sent#${sentReads}`);
        const refused = refusalFor(url.pathname);
        if (refused) return refused;
        return HttpResponse.json(sent);
      }),
      http.post('*/api/v1/chat/conversations/:id/invitations', () => {
        const invitation = {
          id: 'sent-1',
          state: 'pending',
          conversation: room('A'),
          inviter: me,
          invitee: carol,
        };
        sent = [invitation];
        backend.reads.push('POST invite');
        return HttpResponse.json(invitation);
      }),
      http.get('*/api/v2/search', () =>
        HttpResponse.json({ accounts: [carol], statuses: [], hashtags: [] }),
      ),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A/members');
    await waitFor(() => {
      expect(sentReads).toBe(1);
    });
    await settle();
    // A later sent-list read (the inviter's list changed elsewhere) gets 429 Retry-After 60.
    backend.refusals.push({
      path: INVITATIONS,
      status: 429,
      headers: { 'Retry-After': '60' },
    });
    act(() => {
      page.socket.deliver('chat.invitation_update', { conversation_id: 'A' });
    });
    await waitFor(() => {
      expect(sentReads).toBe(2);
    });
    await settle();
    fireEvent.change(screen.getByPlaceholderText('Search for an account'), {
      target: { value: 'carol' },
    });
    await later(1_000);
    fireEvent.click(await screen.findByRole('button', { name: /Carol/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Invite' }));
    await waitFor(() => {
      expect(backend.reads).toContain('POST invite');
    });
    await later(10_000);
    await settle();
    const at10s = {
      pendingCarol: Boolean(
        screen.queryByRole('button', { name: 'Cancel invitation' }),
      ),
      sentReads,
    };
    await later(55_000);
    await settle();
    const at65s = {
      pendingCarol: Boolean(
        screen.queryByRole('button', { name: 'Cancel invitation' }),
      ),
      sentReads,
    };
    await note('N4-invite-under-sent-deadline', { at10s, at65s });
    expect(at10s.pendingCarol).toBe(true);
  }, 90_000);
});

describe('Review a1b5 search matching', () => {
  beforeEach(() => {
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
    server.resetHandlers();
  });

  it('N5 keeps an edited result that the server search still matches (Turkish dotted I)', async () => {
    seed('A', 1, 1);
    const found = { ...message('A', 1), content: 'Istanbul trip' };
    server.use(
      // The server matched with ILIKE (verified on the review DB: 'İstanbul' ILIKE '%istanbul%').
      http.get('*/api/v1/chat/messages/search', () =>
        HttpResponse.json([found]),
      ),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    fireEvent.click(screen.getByRole('button', { name: 'Search messages' }));
    fireEvent.change(screen.getByPlaceholderText('Search messages'), {
      target: { value: 'istanbul' },
    });
    await later(1_000);
    await screen.findByText('Istanbul trip');
    act(() => {
      page.socket.deliver('chat.message_update', {
        ...found,
        content: 'İstanbul trip',
      });
    });
    await settle();
    const shown = document.querySelectorAll(
      '.chat-native__search-results button',
    ).length;
    await note('N5-unicode-case', { resultsAfterEdit: shown });
    expect(shown).toBe(1);
  });

  it('keeps Greek case-folded search results after an edit', async () => {
    seed('A', 1, 1);
    const found = { ...message('A', 1), content: 'ΟΔΟΣ' };
    server.use(
      http.get('*/api/v1/chat/messages/search', () =>
        HttpResponse.json([found]),
      ),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    fireEvent.click(screen.getByRole('button', { name: 'Search messages' }));
    fireEvent.change(screen.getByPlaceholderText('Search messages'), {
      target: { value: 'ΟΔΟΣ' },
    });
    await later(1_000);
    await screen.findByText('ΟΔΟΣ');
    act(() => {
      page.socket.deliver('chat.message_update', {
        ...found,
        content: 'ΟΔΟΣΑ',
      });
    });
    await settle();
    expect(
      document.querySelectorAll('.chat-native__search-results button'),
    ).toHaveLength(1);
  });

  it('N6 an edit while a new query is on its way is judged against the results it changes', async () => {
    seed('A', 1, 2);
    const apple = { ...message('A', 1), content: 'apple pie' };
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    server.use(
      http.get('*/api/v1/chat/messages/search', async ({ request }) => {
        const q = new URL(request.url).searchParams.get('q');
        if (q === 'apple') return HttpResponse.json([apple]);
        await held;
        return HttpResponse.json({ error: 'unavailable' }, { status: 503 });
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    fireEvent.click(screen.getByRole('button', { name: 'Search messages' }));
    const input = screen.getByPlaceholderText('Search messages');
    fireEvent.change(input, { target: { value: 'apple' } });
    await later(1_000);
    await screen.findByText('apple pie');
    fireEvent.change(input, { target: { value: 'banana' } });
    await later(1_000);
    // Still an apple result: edited, it still says apple.
    act(() => {
      page.socket.deliver('chat.message_update', {
        ...apple,
        content: 'apple tart',
      });
    });
    await settle();
    const whileNewQuery = document.querySelectorAll(
      '.chat-native__search-results button',
    ).length;
    await act(async () => {
      release();
      await held;
    });
    await settle();
    const afterFailedQuery = document.querySelectorAll(
      '.chat-native__search-results button',
    ).length;
    await note('N6-query-switch-window', { whileNewQuery, afterFailedQuery });
    expect(whileNewQuery).toBe(1);
  });
});

describe('Pasting text that Safari also supplies as a URI', () => {
  beforeEach(() => {
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
    server.resetHandlers();
  });
  it('inserts the plain text into the composer at its selection and updates React state', async () => {
    seed('A', 1, 1);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 1');
    const box =
      screen.getByPlaceholderText<HTMLTextAreaElement>('Write a message');
    fireEvent.change(box, { target: { value: 'before after' } });
    box.focus();
    box.setSelectionRange(7, 12);
    const exec = vi.fn((_command: string, _ui: boolean, text: string) => {
      box.setRangeText(text, box.selectionStart, box.selectionEnd, 'end');
      box.dispatchEvent(new Event('input', { bubbles: true }));
      return true;
    });
    Object.defineProperty(document, 'execCommand', {
      configurable: true,
      value: exec,
    });
    const plain = 'Note: hello world';
    const accepted = fireEvent.paste(box, {
      clipboardData: {
        types: ['text/plain', 'text/uri-list'],
        files: [],
        items: [],
        getData: (type: string) =>
          type === 'text/plain' ? plain : 'note:%20hello%20world',
      },
    });
    expect(accepted).toBe(false);
    expect(exec).toHaveBeenCalledWith('insertText', false, plain);
    expect(box.value).toBe('before Note: hello world');
    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Send' }).disabled,
    ).toBe(false);
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    await screen.findByText('before Note: hello world');
  }, 30_000);
  it('preserves plain text when editing a message', async () => {
    seed('A', 1, 1);
    backend.messages.set('A', [{ ...message('A', 1), account: me }]);
    let saved = '';
    server.use(
      http.patch('*/api/v1/chat/messages/:id', async ({ request }) => {
        const body = (await request.json()) as { text: string };
        saved = body.text;
        return HttpResponse.json({
          ...message('A', 1),
          account: me,
          content: saved,
        });
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 1');
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
    const box =
      screen.getByPlaceholderText<HTMLTextAreaElement>('Write a message');
    box.focus();
    box.setSelectionRange(0, box.value.length);
    Object.defineProperty(document, 'execCommand', {
      configurable: true,
      value: () => false,
    });
    const plain = 'haru: 확인했어요 — 안녕';
    fireEvent.paste(box, {
      clipboardData: {
        types: ['text/plain', 'text/uri-list'],
        files: [],
        items: [],
        getData: (type: string) =>
          type === 'text/plain'
            ? plain
            : 'haru:%20%ED%99%95%EC%9D%B8%ED%96%88%EC%96%B4%EC%9A%94%20%E2%80%94%20%EC%95%88%EB%85%95',
      },
    });
    expect(box.value).toBe(plain);
    fireEvent.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => {
      expect(saved).toBe(plain);
    });
  });
  it('applies the same narrow correction to a group name input', async () => {
    server.use(
      http.post('*/api/v1/chat/conversations', async ({ request }) => {
        const body = (await request.json()) as { title: string };
        backend.rooms.set('G', {
          title: body.title,
          unread: false,
          type: 'group',
          role: 'owner',
        });
        return HttpResponse.json(room('G'));
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/new');
    fireEvent.click(
      await screen.findByRole('button', { name: 'Create a group' }),
    );
    const input = screen.getByPlaceholderText<HTMLInputElement>('Group name');
    input.focus();
    Object.defineProperty(document, 'execCommand', {
      configurable: true,
      value: () => false,
    });
    fireEvent.paste(input, {
      clipboardData: {
        types: ['text/plain', 'text/uri-list'],
        files: [],
        items: [],
        getData: (type: string) =>
          type === 'text/plain' ? 'Note: hello world' : 'note:%20hello%20world',
      },
    });
    expect(input.value).toBe('Note: hello world');
    fireEvent.click(screen.getByRole('button', { name: 'Create' }));
    await waitFor(() => {
      expect(page.history.location.pathname).toBe('/chat/G');
    });
    expect(backend.rooms.get('G')?.title).toBe('Note: hello world');
  });
  it('leaves an ordinary copied link and a file paste to the browser', async () => {
    seed('A', 1, 1);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 1');
    const box =
      screen.getByPlaceholderText<HTMLTextAreaElement>('Write a message');
    const exec = vi.fn();
    Object.defineProperty(document, 'execCommand', {
      configurable: true,
      value: exec,
    });
    const clipboard = {
      types: ['text/plain', 'text/uri-list'],
      files: [],
      items: [],
      getData: () => 'https://example.test/',
    };
    expect(fireEvent.paste(box, { clipboardData: clipboard })).toBe(true);
    const files = [new File(['x'], 'file.txt')];
    expect(
      fireEvent.paste(box, {
        clipboardData: {
          ...clipboard,
          files,
          getData: (type: string) =>
            type === 'text/plain' ? 'Note: hello' : 'note:%20hello',
        },
      }),
    ).toBe(true);
    expect(
      fireEvent.paste(box, {
        clipboardData: {
          ...clipboard,
          types: ['text/plain'],
          getData: () => 'Note: hello',
        },
      }),
    ).toBe(true);
    expect(
      fireEvent.paste(box, {
        clipboardData: {
          ...clipboard,
          getData: (type: string) =>
            type === 'text/plain' ? 'Note: hello' : 'https://example.test/',
        },
      }),
    ).toBe(true);
    expect(exec).not.toHaveBeenCalled();
  });
});
