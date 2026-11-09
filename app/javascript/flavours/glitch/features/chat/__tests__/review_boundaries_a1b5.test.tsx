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

await vi.hoisted(() => import('../testing/match_media'));

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

const backend = {
  messages: new Map<string, Message[]>(),
  rooms: new Map<
    string,
    { unread: boolean; title: string; type?: 'direct' | 'group'; role?: string }
  >(),
  invitations: [] as { id: string; title: string }[],
  reads: [] as string[],
  marked: [] as string[],
  markAttempts: [] as { room: string; at: number; messageId?: string }[],
  held: [] as { path: RegExp; until: Promise<void> }[],
  failing: [] as RegExp[],
  refusals: [] as {
    path: RegExp;
    status: number;
    headers?: Record<string, string>;
  }[],
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
beforeAll(async () => {
  await import('../index');
}, 60_000);
beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
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

const note = vi.fn().mockResolvedValue(undefined);
const lastId = (id: string) =>
  Number(backend.messages.get(id)?.at(-1)?.id ?? 0);
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
  it('leaves an ordinary copied link and a file paste to the browser, and inserts plain text into the composer at its selection, updating React state', async () => {
    seed('A', 1, 1);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 1');
    const box =
      screen.getByPlaceholderText<HTMLTextAreaElement>('Write a message');
    const untouched = vi.fn();
    Object.defineProperty(document, 'execCommand', {
      configurable: true,
      value: untouched,
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
    expect(untouched).not.toHaveBeenCalled();
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
});

describe('Review f98c boundaries', () => {
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

  it('discards a page from an old cursor after an in-flight list refresh applies', async () => {
    for (let id = 1; id <= 25; id += 1) seed(String(id), id, id);
    useActivityPagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('6');
    });
    await settle();
    backend.messages.set('3', [
      ...(backend.messages.get('3') ?? []),
      message('3', 100),
    ]);
    const releaseRefresh = holdNextAnswer(ROOMS);
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(2);
    });
    const releaseMore = holdNextAnswer(ROOMS);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(3);
    });
    await releaseRefresh();
    await settle();
    await releaseMore();
    await settle();
    await later(1000);
    const button = screen.getByRole('button', { name: 'Load more' });
    expect((button as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(button);
    await waitFor(() => {
      expect(listed()).toHaveLength(25);
    });
    const shown = listed();
    expect(new Set(shown).size).toBe(25);
    expect(shown).toContain('6');
  }, 60000);

  it('keeps a page that finishes before the ongoing list refresh', async () => {
    for (let id = 1; id <= 25; id += 1) seed(String(id), id, id);
    useActivityPagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('6');
    });
    await settle();
    backend.messages.set('3', [
      ...(backend.messages.get('3') ?? []),
      message('3', 100),
    ]);
    const releaseRefresh = holdNextAnswer(ROOMS);
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(2);
    });
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(listed()).toHaveLength(24);
    });
    await releaseRefresh();
    await waitFor(() => {
      expect(listed()).toHaveLength(25);
    });
    expect(new Set(listed()).size).toBe(25);
    expect(listed()).toContain('6');
  }, 60000);

  it('keeps the older cursor aligned when resync replaces an unbridgeable message gap', async () => {
    seed('A', 1, 80);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 80');
    await settle();
    seed('A', 81, 1120);
    const messagesPath = /\/conversations\/A\/messages$/;
    const releaseRefresh = holdNextAnswer(messagesPath);
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(messagesPath).length).toBeGreaterThanOrEqual(2);
    });
    const releaseOlder = holdNextAnswer(messagesPath);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(readsOf(messagesPath).length).toBeGreaterThanOrEqual(3);
    });
    await releaseRefresh();
    await waitFor(
      () => {
        expect(readsOf(messagesPath).length).toBeGreaterThanOrEqual(27);
      },
      { timeout: 10000 },
    );
    await screen.findByText('Message 1120');
    await releaseOlder();
    await settle();
    expect(screen.queryByText('Message 1')).toBeNull();
    const button = screen.getByRole('button', { name: 'Load more' });
    expect((button as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(button);
    await screen.findByText('Message 1041');
  }, 60000);

  it('keeps a held older page when resync bridges to the existing history', async () => {
    seed('A', 1, 80);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 80');
    await settle();
    seed('A', 81, 90);
    const messagesPath = /\/conversations\/A\/messages$/;
    const releaseRefresh = holdNextAnswer(messagesPath);
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(messagesPath).length).toBeGreaterThanOrEqual(2);
    });
    const releaseOlder = holdNextAnswer(messagesPath);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(readsOf(messagesPath).length).toBeGreaterThanOrEqual(3);
    });
    await releaseRefresh();
    await screen.findByText('Message 90');
    await releaseOlder();
    await screen.findByText('Message 1');
    expect(screen.getByText('Message 40')).toBeTruthy();
    expect(screen.getByText('Message 41')).toBeTruthy();
    expect(screen.getByText('Message 90')).toBeTruthy();
  }, 60000);

  it.each([
    ['I\u0307stanbul', 'istanbul', false],
    ['İstanbul', 'istanbul', true],
    ['ΛΟΓΟΣ', 'λογος', false],
    ['λογος', 'λογοσ', false],
    ['λογος', 'λογος', true],
    ['ΟΔΟΣΑ', 'ΟΔΟΣ', true],
    ['li\u0307', 'li', true],
    ['li', 'li\u0307', false],
  ])(
    'matches server ILIKE for edited %s and query %s',
    async (content, query, matches) => {
      seed('A', 1, 1);
      const found = { ...message('A', 1), content: 'initial result' };
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
        target: { value: query },
      });
      await later(1000);
      await screen.findByText('initial result');
      act(() => {
        page.socket.deliver('chat.message_update', { ...found, content });
      });
      await settle();
      expect(
        document.querySelectorAll('.chat-native__search-results button'),
      ).toHaveLength(matches ? 1 : 0);
    },
  );
});

const roomOrder = (a: string, b: string) =>
  lastId(b) - lastId(a) || Number(b) - Number(a);
const useStrictActivityPagedRooms = () => {
  server.use(
    http.get('*/api/v1/chat/conversations', ({ request }) => {
      const url = new URL(request.url);
      backend.reads.push(url.pathname + url.search);
      const maxId = url.searchParams.get('max_id');
      if (maxId && !backend.rooms.has(maxId))
        return HttpResponse.json(
          { error: 'Record not found' },
          { status: 404 },
        );
      return HttpResponse.json(
        [...backend.rooms.keys()]
          .sort(roomOrder)
          .filter(
            (id) =>
              !maxId ||
              lastId(id) < lastId(maxId) ||
              (lastId(id) === lastId(maxId) && Number(id) < Number(maxId)),
          )
          .slice(0, 20)
          .map(room) as never,
      );
    }),
  );
};

const record = vi.fn();
describe('Review 84a6', () => {
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

  it.each([
    ['deleted', 'X1a the owner deletes the group'],
    ['removed', 'X1b the reader is removed from the group'],
  ])(
    'X1 Load more still reads on after the cursor room ends (%s)',
    async (reason, label) => {
      for (let id = 1; id <= 25; id += 1) seed(String(id), id, id);
      useStrictActivityPagedRooms();
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat');
      await waitFor(() => {
        expect(listed()).toContain('6');
      });
      await settle();
      const before = listed();
      backend.rooms.delete('6');
      backend.messages.delete('6');
      act(() => {
        page.socket.deliver('chat.conversation_delete', {
          conversation_id: '6',
          reason,
        });
      });
      await waitFor(() => {
        expect(listed()).not.toContain('6');
      });
      await settle();
      fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
      await later(1_000);
      await settle();
      const afterFirst = listed();
      const noticeFirst = Boolean(screen.queryByText(REQUEST_FAILED));
      const again = screen.queryByRole('button', { name: 'Load more' });
      if (again) {
        fireEvent.click(again);
        await later(1_000);
        await settle();
      }
      const after = listed();
      const serverOrder = [...backend.rooms.keys()].sort(roomOrder);
      record('X1', {
        label,
        before,
        afterFirst,
        noticeFirst,
        after,
        notice: Boolean(screen.queryByText(REQUEST_FAILED)),
        loadMoreButton: Boolean(
          screen.queryByRole('button', { name: 'Load more' }),
        ),
        reads: readsOf(ROOMS),
        missing: serverOrder.filter((id) => !after.includes(id)),
      });
      expect(after).toEqual(serverOrder);
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    },
    60_000,
  );

  it('recovers a missing cursor even if the deletion event was missed', async () => {
    for (let id = 1; id <= 25; id += 1) seed(String(id), id, id);
    useStrictActivityPagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('6');
    });
    backend.rooms.delete('6');
    backend.messages.delete('6');
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(listed()).not.toContain('6');
    });
    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Load more' })).toBeTruthy();
    });
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(listed()).toEqual([...backend.rooms.keys()].sort(roomOrder));
    });
    expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
  }, 60000);

  it('does not restore a room deleted after it received a message during a reread', async () => {
    for (let id = 1; id <= 45; id += 1) seed(String(id), id, id);
    useActivityPagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('26');
    });
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(listed()).toContain('10');
    });
    const releaseFirst = holdNextAnswer(ROOMS);
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS).length).toBeGreaterThanOrEqual(3);
    });
    const newest = message('10', 100);
    backend.messages.set('10', [...(backend.messages.get('10') ?? []), newest]);
    act(() => {
      socket.deliver('chat.message', newest);
    });
    backend.rooms.delete('10');
    backend.messages.delete('10');
    act(() => {
      socket.deliver('chat.conversation_delete', {
        conversation_id: '10',
        reason: 'deleted',
      });
    });
    await releaseFirst();
    await settle();
    await later(1000);
    expect(listed()).not.toContain('10');
    expect(
      backend.reads.filter((read) => read.endsWith('conversations/10')),
    ).toHaveLength(0);
  }, 60000);

  it('X3 a room that gets a message while a two-page list reread is between its pages stays listed', async () => {
    for (let id = 1; id <= 45; id += 1) seed(String(id), id, id);
    useActivityPagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('26');
    });
    await settle();
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(listed()).toContain('6');
    });
    await settle();
    const before = listed();
    const releaseFirst = holdNextAnswer(ROOMS);
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS).length).toBeGreaterThanOrEqual(3);
    });
    const newest = message('10', 100);
    backend.messages.set('10', [...(backend.messages.get('10') ?? []), newest]);
    act(() => {
      socket.deliver('chat.message', newest);
    });
    await settle();
    const whileReading = listed();
    await releaseFirst();
    await settle();
    await later(1_000);
    await settle();
    const after = listed();
    const serverOrder = [...backend.rooms.keys()].sort(roomOrder).slice(0, 40);
    record('X3', {
      before: [before.length, before[0], before.at(-1)],
      whileReading: whileReading.slice(0, 3),
      reads: readsOf(ROOMS),
      after,
      serverFirst40: serverOrder,
      missing: serverOrder.filter((id) => !after.includes(id)),
      detailReads: backend.reads.filter((read) =>
        read.endsWith('conversations/10'),
      ),
    });
    expect(after).toContain('10');
    expect(new Set(after).size).toBe(after.length);
  }, 60_000);

  it('X3b the same when the page is hidden between the reread pages (no answer held)', async () => {
    const setHidden = (hidden: boolean) => {
      Object.defineProperty(document, 'visibilityState', {
        configurable: true,
        get: () => (hidden ? 'hidden' : 'visible'),
      });
      act(() => {
        document.dispatchEvent(new Event('visibilitychange'));
      });
    };
    for (let id = 1; id <= 45; id += 1) seed(String(id), id, id);
    useActivityPagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('26');
    });
    await settle();
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(listed()).toContain('6');
    });
    await settle();
    const releaseFirst = holdNextAnswer(ROOMS);
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS).length).toBeGreaterThanOrEqual(3);
    });
    setHidden(true);
    await releaseFirst();
    await settle();
    const readsWhileHidden = readsOf(ROOMS).length;
    await later(30_000);
    const newest = message('10', 100);
    backend.messages.set('10', [...(backend.messages.get('10') ?? []), newest]);
    act(() => {
      socket.deliver('chat.message', newest);
    });
    await settle();
    setHidden(false);
    await settle();
    await later(1_000);
    await settle();
    const after = listed();
    const serverOrder = [...backend.rooms.keys()].sort(roomOrder).slice(0, 40);
    record('X3b', {
      readsWhileHidden,
      reads: readsOf(ROOMS),
      after: [after.length, after[0], after.at(-1)],
      missing: serverOrder.filter((id) => !after.includes(id)),
    });
    Reflect.deleteProperty(document, 'visibilityState');
    expect(after).toContain('10');
    expect(new Set(after).size).toBe(after.length);
  }, 60_000);
});

const useSnapshotPagedRooms = (hiddenLastRoom?: string) => {
  server.use(
    http.get('*/api/v1/chat/conversations', async ({ request }) => {
      const url = new URL(request.url);
      backend.reads.push(url.pathname + url.search);
      const id = url.searchParams.get('max_id');
      const snapshot = url.searchParams.get('max_id_message_id');
      const missing = Boolean(
        id && snapshot === null && !backend.rooms.has(id),
      );
      const boundary =
        snapshot === null ? (id ? lastId(id) : 0) : Number(snapshot);
      const body = missing
        ? null
        : [...backend.rooms.keys()]
            .sort(roomOrder)
            .filter(
              (roomId) =>
                !id ||
                lastId(roomId) < boundary ||
                (lastId(roomId) === boundary && Number(roomId) < Number(id)),
            )
            .slice(0, 20)
            .map((roomId) => ({
              ...room(roomId),
              ...(roomId === hiddenLastRoom ? { last_message: null } : {}),
            }));
      const cursorMessageId = String(lastId(body?.at(-1)?.id ?? ''));
      const held = take(backend.held, ({ path }) => path.test(url.pathname));
      if (held) await held.until;
      return missing
        ? HttpResponse.json({ error: 'Record not found' }, { status: 404 })
        : HttpResponse.json(body as never, {
            headers: {
              'X-Chat-Cursor-Message-Id': cursorMessageId,
            },
          });
    }),
  );
};
const duplicates = (ids: (string | undefined)[]) =>
  ids.filter((id, index) => ids.indexOf(id) !== index);
const showTwoPages = async () => {
  const page = await loadPage();
  await connect(page.socket);
  page.open('/chat');
  await waitFor(() => {
    expect(listed()).toContain('26');
  });
  await settle();
  fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
  await waitFor(() => {
    expect(listed()).toContain('6');
  });
  await settle();
  return page;
};
const giveMessage = (
  socket: InstanceType<typeof Socket>,
  id: string,
  messageId: number,
) => {
  const newest = message(id, messageId);
  backend.messages.set(id, [...(backend.messages.get(id) ?? []), newest]);
  act(() => {
    socket.deliver('chat.message', newest);
  });
};

describe('Review cursor boundaries', () => {
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
  it('uses the server ordering cursor when the last message is not visible to the viewer', async () => {
    for (let id = 1; id <= 25; id += 1) seed(String(id), id, id);
    useSnapshotPagedRooms('6');
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('6');
    });
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(listed()).toContain('1');
    });
    expect(new Set(listed()).size).toBe(25);
  }, 60_000);
  it('C1 the reread page cursor room itself gets a message between reread pages', async () => {
    for (let id = 1; id <= 45; id += 1) seed(String(id), id, id);
    useSnapshotPagedRooms();
    const page = await showTwoPages();
    const before = listed();
    const releaseFirst = holdNextAnswer(ROOMS);
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS).length).toBeGreaterThanOrEqual(3);
    });
    giveMessage(socket, '26', 100);
    await settle();
    const whileReading = listed();
    await releaseFirst();
    await settle();
    await later(1_000);
    await settle();
    const after = listed();
    const serverFirst40 = [...backend.rooms.keys()]
      .sort(roomOrder)
      .slice(0, 40);
    record('C1', {
      before: [before.length, before[0], before.at(-1)],
      whileReading: whileReading.slice(0, 3),
      reads: readsOf(ROOMS),
      after,
      length: after.length,
      duplicates: duplicates(after),
      serverFirst40,
      missing: serverFirst40.filter((id) => !after.includes(id)),
    });
    expect(duplicates(after)).toEqual([]);
    expect(after).toEqual(serverFirst40);
  }, 60_000);

  it('C2 Load more after the cursor room got a message reads on past the shown rooms', async () => {
    for (let id = 1; id <= 45; id += 1) seed(String(id), id, id);
    useSnapshotPagedRooms();
    const page = await showTwoPages();
    giveMessage(page.socket, '6', 100);
    await waitFor(() => {
      expect(listed()[0]).toBe('6');
    });
    await settle();
    const before = listed();
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await later(1_000);
    await settle();
    const afterFirst = listed();
    record('C2', {
      before: [before.length, before[0], before.at(-1)],
      reads: readsOf(ROOMS),
      afterFirst: [afterFirst.length, afterFirst.at(-1)],
      added: afterFirst.filter((id) => !before.includes(id)),
      loadMoreButton: Boolean(
        screen.queryByRole('button', { name: 'Load more' }),
      ),
    });
    expect(afterFirst.filter((id) => !before.includes(id))).toEqual([
      '5',
      '4',
      '3',
      '2',
      '1',
    ]);
  }, 60_000);

  it('C3 the reread on reconnect survives its page cursor room ending between pages', async () => {
    for (let id = 1; id <= 45; id += 1) seed(String(id), id, id);
    useSnapshotPagedRooms();
    const page = await showTwoPages();
    const releaseFirst = holdNextAnswer(ROOMS);
    const socket = await dropConnection(page.socket);
    seed('50', 200, 200);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS).length).toBeGreaterThanOrEqual(3);
    });
    backend.rooms.delete('27');
    backend.messages.delete('27');
    act(() => {
      socket.deliver('chat.conversation_delete', {
        conversation_id: '27',
        reason: 'deleted',
      });
    });
    await settle();
    await releaseFirst();
    await settle();
    await later(40_000);
    await settle();
    const after = listed();
    const serverFirst40 = [...backend.rooms.keys()]
      .sort(roomOrder)
      .slice(0, 40);
    record('C3', {
      reads: readsOf(ROOMS),
      after,
      notice: Boolean(screen.queryByText(REQUEST_FAILED)),
      serverFirst40,
      missing: serverFirst40.filter((id) => !after.includes(id)),
    });
    expect(after).toContain('50');
    expect(after).toEqual(serverFirst40.slice(0, after.length));
    if (after.length < serverFirst40.length) {
      fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
      await waitFor(() => {
        expect(listed().slice(0, 40)).toEqual(serverFirst40);
      });
    }
    expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
  }, 90_000);

  it('C4 a room in the Load more page that gets a message before that page lands goes to the top', async () => {
    for (let id = 1; id <= 45; id += 1) seed(String(id), id, id);
    useSnapshotPagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('26');
    });
    await settle();
    const releaseMore = holdNextAnswer(ROOMS);
    const releaseDetail = holdNextAnswer(/\/conversations\/10$/);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(readsOf(ROOMS).length).toBeGreaterThanOrEqual(2);
    });
    giveMessage(page.socket, '10', 100);
    await settle();
    await releaseMore();
    await settle();
    await releaseDetail();
    await settle();
    await later(1_000);
    await settle();
    const after = listed();
    record('C4', {
      reads: backend.reads,
      after,
      position10: after.indexOf('10'),
      duplicates: duplicates(after),
    });
    expect(duplicates(after)).toEqual([]);
    expect(after[0]).toBe('10');
  }, 60_000);
});

const sortKey = new Map<string, number>();
const visible = new Map<string, number>();
const shown = (id: string) => ({
  ...room(id),
  last_message: visible.has(id) ? message(id, visible.get(id) ?? 0) : null,
});
const useSortKeyRooms = () => {
  server.use(
    http.get(
      '*/api/v1/chat/conversations',
      answer(() =>
        [...backend.rooms.keys()]
          .sort(
            (a, b) =>
              (sortKey.get(b) ?? 0) - (sortKey.get(a) ?? 0) ||
              Number(b) - Number(a),
          )
          .slice(0, 20)
          .map(shown),
      ),
    ),
    http.get(
      '*/api/v1/chat/conversations/:id',
      answer((_, id) => shown(id)),
    ),
  );
};
const put = (id: string, key: number, seen: number) => {
  backend.rooms.set(id, { title: `Room ${id}`, unread: false, type: 'group' });
  sortKey.set(id, key);
  visible.set(id, seen);
};
const serverOrder = () =>
  [...backend.rooms.keys()].sort(
    (a, b) =>
      (sortKey.get(b) ?? 0) - (sortKey.get(a) ?? 0) || Number(b) - Number(a),
  );

describe('Review 2963', () => {
  beforeEach(() => {
    sortKey.clear();
    visible.clear();
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
    server.resetHandlers();
  });

  it('D1 a room update keeps the server order when another room shows an older message than it is sorted by', async () => {
    put('50', 200, 200);
    put('40', 190, 10);
    put('30', 180, 180);
    put('20', 170, 170);
    put('10', 160, 160);
    useSortKeyRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('10');
    });
    await settle();
    const loaded = listed();
    act(() => {
      page.socket.deliver('chat.conversation_update', {
        ...shown('10'),
        title: 'Renamed',
      });
    });
    await settle();
    const after = listed();
    record({ test: 'D1', loaded, after, server: serverOrder() });
    expect(loaded).toEqual(serverOrder());
    expect(after).toEqual(serverOrder());
  });

  it('D1b hiding my own last message keeps the room where a reread puts it', async () => {
    put('3', 300, 300);
    put('2', 200, 200);
    put('1', 100, 100);
    useSortKeyRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toEqual(['3', '2', '1']);
    });
    await settle();
    visible.set('3', 50);
    const detailsBefore = readsOf(/\/conversations\/3$/).length;
    act(() => {
      page.socket.deliver('chat.message_hide', {
        id: '300',
        conversation_id: '3',
      });
    });
    await waitFor(() => {
      expect(readsOf(/\/conversations\/3$/).length).toBeGreaterThan(
        detailsBefore,
      );
    });
    await settle();
    const live = listed();
    const listReads = readsOf(ROOMS).length;
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS).length).toBeGreaterThan(listReads);
    });
    await later(500);
    await settle();
    const reread = listed();
    record({ test: 'D1b', live, reread, server: serverOrder() });
    expect(live).toEqual(reread);
  });
});

const script: { hold?: Promise<void>; status?: number }[] = [];
const useScriptedSnapshotRooms = () => {
  server.use(
    http.get('*/api/v1/chat/conversations', async ({ request }) => {
      const url = new URL(request.url);
      backend.reads.push(url.pathname + url.search);
      const step = script.shift();
      const id = url.searchParams.get('max_id');
      const snapshot = url.searchParams.get('max_id_message_id');
      const boundary =
        snapshot === null ? (id ? lastId(id) : 0) : Number(snapshot);
      const body = [...backend.rooms.keys()]
        .sort(roomOrder)
        .filter(
          (roomId) =>
            !id ||
            lastId(roomId) < boundary ||
            (lastId(roomId) === boundary && Number(roomId) < Number(id)),
        )
        .slice(0, 20)
        .map((roomId) => room(roomId));
      if (step?.hold) await step.hold;
      if (step?.status === 429)
        return HttpResponse.json(
          { error: 'test 429' },
          { status: 429, headers: { 'Retry-After': '20' } },
        );
      return HttpResponse.json(body as never, {
        headers: {
          'X-Chat-Cursor-Message-Id': String(lastId(body.at(-1)?.id ?? '')),
        },
      });
    }),
  );
};
const gate = () => {
  let release!: () => void;
  const hold = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { hold, release };
};

describe('Review 355b list', () => {
  beforeEach(() => {
    script.length = 0;
    vi.useFakeTimers({
      shouldAdvanceTime: true,
      toFake: ['setTimeout', 'clearTimeout', 'Date'],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
    server.resetHandlers();
  });

  for (const second of [false, true]) {
    it(`L1 late 429 from a left screen, then the reread waits for the deadline (${second ? 'two' : 'one'} reread signals)`, async () => {
      for (let id = 1; id <= 45; id += 1) seed(String(id), id, id);
      useScriptedSnapshotRooms();
      const page = await loadPage();
      await connect(page.socket);
      const stale = gate();
      script.push({ hold: stale.hold, status: 429 });
      page.open('/chat');
      await waitFor(() => {
        expect(readsOf(ROOMS).length).toBe(1);
      });
      act(() => {
        page.history.push('/home');
      });
      await settle();
      act(() => {
        page.history.push('/chat');
      });
      await waitFor(() => {
        expect(listed()).toContain('26');
      });
      await settle();
      fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
      await waitFor(() => {
        expect(listed()).toContain('6');
      });
      await settle();
      const reread = gate();
      script.push({ hold: reread.hold });
      const socket = await dropConnection(page.socket);
      const before = readsOf(ROOMS).length;
      await connect(socket);
      await waitFor(() => {
        expect(readsOf(ROOMS).length).toBe(before + 1);
      });
      if (second)
        await act(async () => {
          socket.subscribed();
          await Promise.resolve();
        });
      await settle();
      await act(async () => {
        stale.release();
        await stale.hold;
      });
      await settle();
      await act(async () => {
        reread.release();
        await reread.hold;
      });
      await settle();
      const atRelease = readsOf(ROOMS).length;
      await later(19_000);
      const beforeDeadline = readsOf(ROOMS).slice(atRelease);
      await later(6_000);
      await settle();
      await later(2_000);
      await settle();
      const afterDeadline = readsOf(ROOMS).slice(atRelease);
      const after = listed();
      expect(beforeDeadline).toEqual([]);
      expect(duplicates(after)).toEqual([]);
      const cursorReads = afterDeadline.filter((read) =>
        read.includes('max_id='),
      );
      expect(cursorReads.length).toBe(1);
    }, 90_000);
  }
});
