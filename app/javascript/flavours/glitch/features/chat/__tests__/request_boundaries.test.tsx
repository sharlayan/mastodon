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

const MEDIA = /\/api\/v1\/media\/m1$/;
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

const record = vi.fn();
const listed = () =>
  [...document.querySelectorAll('[data-conversation-id]')].map(
    (node) => (node as HTMLElement).dataset.conversationId,
  );
const numericRooms = (count: number) => {
  for (let id = 1; id <= count; id += 1) seed(String(id), 1, 1);
};
const usePagedRooms = () => {
  server.use(
    http.get(
      '*/api/v1/chat/conversations',
      answer((url) => {
        const maxId = url.searchParams.get('max_id');
        return [...backend.rooms.keys()]
          .sort((a, b) => Number(b) - Number(a))
          .filter((id) => !maxId || Number(id) < Number(maxId))
          .slice(0, 20)
          .map(room);
      }),
    ),
  );
};
const INVITATIONS = /\/invitations$/;

describe('Review a99b', () => {
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

  it('does not restore a deleted message from an older search answer', async () => {
    seed('A', 1, 1);
    const found = { ...message('A', 1), content: 'A unique search result' };
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
      page.socket.deliver('chat.message_delete', {
        id: '1',
        conversation_id: 'A',
      });
    });
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(screen.queryByText('A unique search result')).toBeNull();
  });

  it('does not restore search results from a deleted conversation', async () => {
    seed('A', 1, 1);
    const found = { ...message('A', 1), content: 'A unique search result' };
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
      page.socket.deliver('chat.conversation_delete', { conversation_id: 'A' });
    });
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(screen.queryByText('A unique search result')).toBeNull();
  });

  it('keeps a message edit that arrives before an older search answer', async () => {
    seed('A', 1, 1);
    const found = { ...message('A', 1), content: 'A unique search result' };
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
      page.socket.deliver('chat.message_update', {
        ...found,
        content: 'A unique edited result',
      });
    });
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(
      document.querySelector('.chat-native__search-results')?.textContent,
    ).toContain('A unique edited result');
  });

  it('drops an edited search result that no longer matches the query', async () => {
    seed('A', 1, 1);
    const found = { ...message('A', 1), content: 'A unique search result' };
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
      page.socket.deliver('chat.message_update', {
        ...found,
        content: 'Changed text',
      });
    });
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(
      document.querySelectorAll('.chat-native__search-results button'),
    ).toHaveLength(0);
  });

  it('does not restore a cancelled sent invitation from a read already in flight', async () => {
    seed('A', 1, 1);
    backend.rooms.set('A', {
      title: 'Room A',
      unread: false,
      type: 'group',
      role: 'owner',
    });
    const carol = person('carol', 'Carol');
    let invitations = [
      {
        id: 'sent-1',
        state: 'pending',
        conversation: room('A'),
        inviter: me,
        invitee: carol,
      },
    ];
    let reads = 0;
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    server.use(
      http.get('*/api/v1/chat/invitations', async ({ request }) => {
        if (new URL(request.url).searchParams.get('direction') !== 'sent')
          return HttpResponse.json([]);
        const snapshot = [...invitations];
        reads += 1;
        if (reads === 2) await held;
        return HttpResponse.json(snapshot);
      }),
      http.delete('*/api/v1/chat/invitations/:id', () => {
        invitations = [];
        return HttpResponse.json({});
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A/members');
    await screen.findByText('Carol');
    act(() => {
      page.socket.deliver('chat.invitation_update', { conversation_id: 'A' });
    });
    await waitFor(() => {
      expect(reads).toBe(2);
    });
    fireEvent.click(screen.getByRole('button', { name: 'Cancel invitation' }));
    await waitFor(() => {
      expect(screen.queryByText('Carol')).toBeNull();
    });
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(screen.queryByText('Carol')).toBeNull();
  });

  it('keeps a newer settings change when an older successful patch arrives late', async () => {
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    let patches = 0;
    let state = {
      policy: 'everyone',
      allow_group_invites: true,
      notifications: true,
      max_group_members: 10,
      max_attachments: 4,
      federation_enabled: true,
      delete_window_hours: 24,
      soft_delete: false,
    };
    server.use(
      http.patch('*/api/v1/chat/settings', async ({ request }) => {
        state = {
          ...state,
          ...((await request.json()) as Partial<typeof state>),
        };
        const snapshot = { ...state };
        patches += 1;
        if (patches === 1) await held;
        return HttpResponse.json(snapshot);
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(
        document.querySelector('#setting-toggle-chat-allow_group_invites'),
      ).toBeTruthy();
    });
    const group = document.querySelector(
      '#setting-toggle-chat-allow_group_invites',
    ) as HTMLInputElement;
    const notifications = document.querySelector(
      '#setting-toggle-chat-notifications',
    ) as HTMLInputElement;
    fireEvent.click(group);
    await waitFor(() => {
      expect(patches).toBe(1);
    });
    fireEvent.click(notifications);
    await waitFor(() => {
      expect(notifications.checked).toBe(false);
    });
    await act(async () => {
      release();
      await held;
    });
    await settle();
    expect(group.checked).toBe(false);
    expect(notifications.checked).toBe(false);
  });

  it('S1 a list read after a user action, overtaken by a newer applied read, raises no notice when it fails late', async () => {
    seed('A', 1, 1);
    backend.invitations = [{ id: 'invite', title: 'Invited room' }];
    server.use(
      http.post('*/api/v1/chat/invitations/:id/accept', () =>
        HttpResponse.json({}),
      ),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    await settle();
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );
    await screen.findByText('Invited room');
    backend.refusals.push({
      path: ROOMS,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    const release = holdNextAnswer(ROOMS);
    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(2);
    });
    await settle();
    backend.rooms.set('B', { title: 'Room B', unread: false });
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(3);
    });
    await settle();
    fireEvent.click(screen.getByRole('button', { name: /^Home/ }));
    await screen.findByText('Room B');
    const noticeBeforeRelease = Boolean(screen.queryByText(REQUEST_FAILED));
    await release();
    await settle();
    const noticeAfterRelease = Boolean(screen.queryByText(REQUEST_FAILED));
    const listAfterRelease = listed();
    await later(10_000);
    const at10s = {
      notice: Boolean(screen.queryByText(REQUEST_FAILED)),
      roomReads: readsOf(ROOMS).length,
    };
    await later(11_000);
    await settle();
    const at21s = {
      notice: Boolean(screen.queryByText(REQUEST_FAILED)),
      roomReads: readsOf(ROOMS).length,
    };
    record('S1-overtaken-user-read-fails-late', {
      noticeBeforeRelease,
      noticeAfterRelease,
      listAfterRelease,
      at10s,
      at21s,
    });
    expect(noticeBeforeRelease).toBe(false);
    expect(noticeAfterRelease).toBe(false);
    expect(at10s.roomReads).toBe(3);
  }, 30_000);

  it('S1b the opening list read, overtaken by a newer applied read, raises no notice when it fails late', async () => {
    seed('A', 1, 1);
    backend.invitations = [{ id: 'invite', title: 'Invited room' }];
    server.use(
      http.post('*/api/v1/chat/invitations/:id/accept', () =>
        HttpResponse.json({}),
      ),
    );
    backend.failing.push(ROOMS);
    const release = holdNextAnswer(ROOMS);
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(1);
    });
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );
    await screen.findByText('Invited room');
    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(2);
    });
    await settle();
    fireEvent.click(screen.getByRole('button', { name: /^Home/ }));
    await screen.findByText('Room A');
    const noticeBeforeRelease = Boolean(screen.queryByText(REQUEST_FAILED));
    await release();
    await settle();
    const noticeAfterRelease = Boolean(screen.queryByText(REQUEST_FAILED));
    await later(3_000);
    await settle();
    const after3s = {
      notice: Boolean(screen.queryByText(REQUEST_FAILED)),
      roomReads: readsOf(ROOMS).length,
    };
    record('S1b-overtaken-opening-read-fails-late', {
      noticeBeforeRelease,
      noticeAfterRelease,
      after3s,
    });
    expect(noticeAfterRelease).toBe(false);
  }, 30_000);

  it('S2 a Load more answer that arrives after a room was deleted does not bring the room back', async () => {
    numericRooms(25);
    usePagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('25');
    });
    await settle();
    const before = listed();
    const release = holdNextAnswer(ROOMS);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(2);
    });
    backend.rooms.delete('3');
    act(() => {
      page.socket.deliver('chat.conversation_delete', { conversation_id: '3' });
    });
    await settle();
    await release();
    await settle();
    const after = listed();
    record('S2-load-more-after-delete', {
      before: before.length,
      had3Before: before.includes('3'),
      after: after.length,
      has3After: after.includes('3'),
      reads: readsOf(ROOMS),
    });
    expect(after.includes('3')).toBe(false);
  }, 30_000);

  it('S3a an invitations answer that arrives after the group was deleted does not bring its invitation back', async () => {
    seed('A', 1, 1);
    backend.invitations = [{ id: 'G1', title: 'Group one' }];
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    await settle();
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );
    await screen.findByText('Group one');
    const release = holdNextAnswer(INVITATIONS);
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'other' });
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS).length).toBeGreaterThanOrEqual(2);
    });
    backend.invitations = [];
    act(() => {
      page.socket.deliver('chat.conversation_delete', {
        conversation_id: 'G1',
        reason: 'deleted',
      });
    });
    await settle();
    const goneAfterEvent = !screen.queryByText('Group one');
    await release();
    await settle();
    const back = Boolean(screen.queryByText('Group one'));
    record('S3a-invitations-after-delete', {
      goneAfterEvent,
      back,
      reads: readsOf(INVITATIONS),
    });
    expect(goneAfterEvent).toBe(true);
    expect(back).toBe(false);
  }, 30_000);

  it('S3b an invitations answer that left before an accept does not bring the accepted invitation back', async () => {
    seed('A', 1, 1);
    backend.invitations = [{ id: 'G1', title: 'Group one' }];
    server.use(
      http.post('*/api/v1/chat/invitations/:id/accept', () => {
        backend.invitations = [];
        backend.reads.push('POST accept');
        return HttpResponse.json({});
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    await settle();
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );
    await screen.findByText('Group one');
    const release = holdNextAnswer(INVITATIONS);
    act(() => {
      page.socket.deliver('chat.invitation', { id: 'other' });
    });
    await waitFor(() => {
      expect(readsOf(INVITATIONS).length).toBeGreaterThanOrEqual(2);
    });
    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
    await waitFor(() => {
      expect(backend.reads).toContain('POST accept');
    });
    await settle();
    const goneAfterAccept = !screen.queryByText('Group one');
    await release();
    await settle();
    const back = Boolean(screen.queryByText('Group one'));
    record('S3b-invitations-after-accept', { goneAfterAccept, back });
    expect(goneAfterAccept).toBe(true);
    expect(back).toBe(false);
  }, 30_000);

  it('S4 a 429 on Load more keeps the server deadline for the next background list read, and Load more waits for that read before retrying', async () => {
    numericRooms(25);
    usePagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await waitFor(() => {
      expect(listed()).toContain('25');
    });
    await settle();
    backend.refusals.push({
      path: ROOMS,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText(REQUEST_FAILED);
    expect(readsOf(ROOMS)).toHaveLength(2);
    await settle();
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await later(1_000);
    const within = readsOf(ROOMS);
    record('S4-load-more-429', {
      roomReadsWithin1s: within.length,
      reads: within,
      notice: Boolean(screen.queryByText(REQUEST_FAILED)),
    });
    expect(within).toHaveLength(2);

    const release = holdNextAnswer(ROOMS);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await later(20_500);
    await settle();
    expect(readsOf(ROOMS)).toHaveLength(3);
    await release();
    await screen.findByText('Room 1');
    await waitFor(() => {
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    });
  }, 30_000);

  it('S4b a 429 on loading older messages keeps the server deadline for the next resync, and older messages wait for that resync before retrying', async () => {
    seed('A', 1, 45);
    const MESSAGES = /\/conversations\/A\/messages$/;
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 45');
    await settle();
    const before = readsOf(MESSAGES).length;
    backend.refusals.push({
      path: MESSAGES,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText(REQUEST_FAILED);
    expect(readsOf(MESSAGES)).toHaveLength(before + 1);
    await settle();
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await later(1_000);
    const within = readsOf(MESSAGES).slice(before);
    record('S4b-older-messages-429', {
      messageReadsAfterLoadMore: within,
    });
    expect(within).toHaveLength(1);

    const release = holdNextAnswer(MESSAGES);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await later(20_500);
    await settle();
    expect(readsOf(MESSAGES)).toHaveLength(before + 2);
    await release();
    await screen.findByText('Message 1');
    await waitFor(() => {
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    });
  }, 30_000);

  it('clears the Load more reading error when the same page later succeeds', async () => {
    numericRooms(25);
    usePagedRooms();
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room 25');
    backend.refusals.push({
      path: ROOMS,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText(REQUEST_FAILED);
    await later(20_000);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText('Room 1');
    await waitFor(() => {
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    });
  }, 30_000);
  it('clears the older-message error when the same page later succeeds', async () => {
    seed('A', 1, 45);
    const MESSAGES = /\/conversations\/A\/messages$/;
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 45');
    backend.refusals.push({
      path: MESSAGES,
      status: 429,
      headers: { 'Retry-After': '20' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText(REQUEST_FAILED);
    await later(20_000);
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText('Message 1');
    await waitFor(() => {
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    });
  }, 30_000);
  it('S5 a successful mute shows on the room menu without waiting out a list read deadline', async () => {
    seed('A', 1, 1);
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
        return HttpResponse.json(withMute(String(params.id)));
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 1');
    await screen.findByRole('button', { name: 'Mute' });
    await settle();
    backend.refusals.push({
      path: ROOMS,
      status: 429,
      headers: { 'Retry-After': '120' },
    });
    const socket = await dropConnection(page.socket);
    await connect(socket);
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(2);
    });
    await settle();
    fireEvent.click(screen.getByRole('button', { name: 'Mute' }));
    await waitFor(() => {
      expect(backend.reads).toContain('POST mute');
    });
    await later(10_000);
    const state = () => ({
      mute: Boolean(screen.queryByRole('button', { name: 'Mute' })),
      unmute: Boolean(screen.queryByRole('button', { name: 'Unmute' })),
      serverMuted: muted.has('A'),
      roomReads: readsOf(ROOMS).length,
      notice: Boolean(screen.queryByText(REQUEST_FAILED)),
    });
    const at10s = state();
    await later(115_000);
    await settle();
    const at125s = state();
    record('S5-mute-under-deadline', { at10s, at125s });
    expect(at10s.unmute).toBe(true);
    expect(at125s.roomReads).toBe(3);
  }, 30_000);

  it('S6 jumping to an old search result reads no older page while the tab is hidden', async () => {
    seed('A', 1, 200);
    const olderReads: { maxId: string; hidden: boolean }[] = [];
    let releaseFirst: (() => void) | undefined;
    let firstHeld: Promise<void> | undefined;
    server.use(
      http.get(
        '*/api/v1/chat/conversations/:id/messages',
        async ({ request, params }) => {
          const url = new URL(request.url);
          backend.reads.push(url.pathname + url.search);
          const before = url.searchParams.get('max_id');
          const list = (backend.messages.get(String(params.id)) ?? [])
            .filter((item) => !before || Number(item.id) < Number(before))
            .slice(-PAGE);
          if (before) {
            olderReads.push({
              maxId: before,
              hidden: document.visibilityState === 'hidden',
            });
            if (!firstHeld) {
              firstHeld = new Promise((resolve) => {
                releaseFirst = resolve;
              });
              await firstHeld;
            }
          }
          return HttpResponse.json(list);
        },
      ),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat');
    await screen.findByText('Room A');
    await settle();
    act(() => {
      page.history.push('/chat/A', { chatMessageId: '3' });
    });
    await waitFor(() => {
      expect(olderReads).toHaveLength(1);
    });
    setHidden(true);
    await act(async () => {
      releaseFirst?.();
      await firstHeld;
    });
    await settle();
    await later(5_000);
    const whileHidden = olderReads.filter((read) => read.hidden);
    setHidden(false);
    await later(5_000);
    await settle();
    record('S6-jump-pages-while-hidden', {
      olderReads,
      olderReadsWhileHidden: whileHidden.length,
      targetLoaded: Boolean(document.getElementById('chat-message-3')),
    });
    expect(whileHidden).toHaveLength(0);
    expect(document.getElementById('chat-message-3')).toBeTruthy();
  }, 30_000);

  it('S7 attaches each successful file when another file is refused', async () => {
    seed('A', 1, 1);
    let polls = 0;
    server.use(
      http.get('*/api/v1/media/:id', ({ request }) => {
        backend.reads.push(new URL(request.url).pathname);
        polls += 1;
        const ready = polls >= 4;
        return HttpResponse.json(
          {
            id: 'm1',
            type: 'video',
            url: ready ? '/m1.webm' : null,
            preview_url: null,
            description: null,
          },
          { status: ready ? 200 : 206 },
        );
      }),
    );
    const page = await loadPage();
    await connect(page.socket);
    page.open('/chat/A');
    await screen.findByText('Message 1');
    await waitFor(() => {
      expect(readsOf(/\/settings$/).length).toBeGreaterThan(0);
    });
    await settle();
    const input = document.querySelector(
      'input[type="file"]',
    ) as HTMLInputElement;
    fireEvent.change(input, {
      target: {
        files: [
          new File(['x'], 'shapes.webm', { type: 'video/webm' }),
          new File(['y'], 'bad.webm', { type: 'video/webm' }),
        ],
      },
    });
    await screen.findByText(REQUEST_FAILED);
    const atError = readsOf(MEDIA).length;
    await later(6_000);
    await settle();
    const afterError = readsOf(MEDIA).length - atError;
    record('S7-batch-upload-partial-failure', {
      pollsBeforeError: atError,
      pollsAfterError: afterError,
      attached: document.querySelectorAll('[data-media-id]').length,
      notice: Boolean(screen.queryByText(REQUEST_FAILED)),
    });
    expect(afterError).toBeGreaterThan(0);
    expect(document.querySelectorAll('[data-media-id]')).toHaveLength(1);
  }, 30_000);

  it('S8 (observation) going back to a created room shows the creation snapshot until the list is read', async () => {
    seed('A', 1, 1);
    server.use(
      http.post('*/api/v1/chat/conversations', () => {
        backend.reads.push('POST /api/v1/chat/conversations');
        backend.rooms.set('G', {
          title: 'Room G',
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
    await waitFor(() => {
      expect(readsOf(ROOMS)).toHaveLength(1);
    });
    await settle();
    fireEvent.click(
      await screen.findByRole('button', { name: 'Create a group' }),
    );
    fireEvent.change(screen.getByPlaceholderText('Group name'), {
      target: { value: 'Room G' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Create' }));
    await waitFor(() => {
      expect(page.history.location.pathname).toBe('/chat/G');
    });
    const titleAtCreate = screen.getByTestId('column-title').textContent;
    backend.rooms.set('G', {
      title: 'Renamed G',
      unread: false,
      type: 'group',
      role: 'owner',
    });
    act(() => {
      page.history.push('/chat');
    });
    await screen.findByText('Renamed G');
    backend.refusals.push({
      path: ROOMS,
      status: 429,
      headers: { 'Retry-After': '60' },
    });
    act(() => {
      page.history.goBack();
    });
    await settle();
    const titleAfterBack = screen.getByTestId('column-title').textContent;
    const stateAfterBack = page.history.location.state;
    await later(30_000);
    const titleAt30s = screen.getByTestId('column-title').textContent;
    await later(31_000);
    await settle();
    const titleAt61s = screen.getByTestId('column-title').textContent;
    record('S8-back-to-created-room', {
      titleAtCreate,
      titleAfterBack,
      titleAt30s,
      titleAt61s,
      stateHasSnapshot: Boolean(
        (stateAfterBack as { chatCreatedConversation?: unknown } | undefined)
          ?.chatCreatedConversation,
      ),
    });
    expect(titleAfterBack).not.toContain('Room G');
  }, 30_000);
});
