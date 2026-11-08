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

describe('Chat recovery and request lifecycles', () => {
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

  describe('waitForMedia: attachment still processing', () => {
    beforeEach(() => {
      server.use(
        http.post('*/api/v2/media', () => {
          backend.reads.push('POST /api/v2/media');
          return HttpResponse.json(
            {
              id: 'm1',
              type: 'video',
              url: null,
              preview_url: null,
              description: null,
            },
            { status: 202 },
          );
        }),
        http.get('*/api/v1/media/:id', ({ request }) => {
          backend.reads.push(new URL(request.url).pathname);
          return HttpResponse.json(
            {
              id: 'm1',
              type: 'video',
              url: null,
              preview_url: null,
              description: null,
            },
            { status: 206 },
          );
        }),
      );
    });
    const startUpload = async () => {
      seed('A', 1, 1);
      seed('B', 1, 1);
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
          files: [new File(['x'], 'shapes.webm', { type: 'video/webm' })],
        },
      });
      await settle();
      await waitFor(() => {
        expect(readsOf(MEDIA)).toHaveLength(1);
      });
      return page;
    };
    it('keeps polling an upload while the tab is hidden', async () => {
      await startUpload();
      await later(1_500);
      setHidden(true);
      const atHide = readsOf(MEDIA).length;
      await later(5_000);
      const whileHidden = readsOf(MEDIA).length - atHide;
      expect(whileHidden).toBeGreaterThan(0);
    }, 30_000);
    it('starts no media status GET after leaving the room', async () => {
      const page = await startUpload();
      act(() => {
        page.history.push('/chat/B');
      });
      await screen.findByText('Room B');
      const atLeave = readsOf(MEDIA).length;
      await later(5_000);
      const afterLeave = readsOf(MEDIA).length - atLeave;
      expect(afterLeave).toBe(0);
    }, 30_000);
    it('starts no media status GET after the chat screen closes', async () => {
      const page = await startUpload();
      act(() => {
        page.history.push('/elsewhere');
      });
      const atClose = readsOf(MEDIA).length;
      await later(5_000);
      const afterClose = readsOf(MEDIA).length - atClose;
      expect(afterClose).toBe(0);
    }, 30_000);
  });

  describe('conversations: background retry overtaken by a user action', () => {
    it('clears the reading notice once the list has been read again', async () => {
      seed('A', 1, 1);
      backend.invitations = [{ id: 'invite', title: 'Invited room' }];
      server.use(
        http.post('*/api/v1/chat/invitations/:id/accept', () =>
          HttpResponse.json({}),
        ),
      );
      backend.failing.push(ROOMS);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat');
      await screen.findByText(REQUEST_FAILED);
      const releaseRetry = holdNextAnswer(ROOMS);
      await later(2_100);
      await waitFor(() => {
        expect(readsOf(ROOMS)).toHaveLength(2);
      });
      fireEvent.click(
        await screen.findByRole('button', { name: /Invitations\s*1/ }),
      );
      await screen.findByText('Invited room');
      fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
      await waitFor(() => {
        expect(readsOf(ROOMS)).toHaveLength(3);
      });
      await settle();
      await releaseRetry();
      await settle();
      await later(60_000);
      const onInvitationsTab = [
        ...document.querySelectorAll('[data-conversation-id]'),
      ].length;
      fireEvent.click(screen.getByRole('button', { name: /^Home/ }));
      await settle();
      const state = {
        onInvitationsTab,
        roomReads: readsOf(ROOMS).length,
        notice: Boolean(screen.queryByText(REQUEST_FAILED)),
        listed: [...document.querySelectorAll('[data-conversation-id]')].map(
          (node) => (node as HTMLElement).dataset.conversationId,
        ),
      };
      expect(state.notice).toBe(false);
    }, 30_000);
  });

  describe('conversations: 429 on the read after a user action', () => {
    it('keeps the server deadline for the next background list read', async () => {
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
      fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
      await waitFor(() => {
        expect(readsOf(ROOMS)).toHaveLength(2);
      });
      await settle();
      const socket = await dropConnection(page.socket);
      await connect(socket);
      await later(1_000);
      const before = backend.reads.filter((read) =>
        (read.split('?')[0] ?? '').endsWith('/conversations'),
      ).length;
      expect(before).toBe(2);
    }, 30_000);
  });
  describe('successful write followed by failed list refresh', () => {
    it('clears the read notice after the failed refresh recovers', async () => {
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
      fireEvent.click(
        await screen.findByRole('button', { name: /Invitations\s*1/ }),
      );
      backend.down.push(ROOMS);
      fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
      await screen.findByText(REQUEST_FAILED);
      backend.down = [];
      const socket = await dropConnection(page.socket);
      await connect(socket);
      await waitFor(() => {
        expect(readsOf(ROOMS).length).toBeGreaterThanOrEqual(3);
      });
      await settle();
      expect(screen.queryByText(REQUEST_FAILED)).toBeNull();
    }, 30_000);
  });
  describe('a failed user write', () => {
    it('keeps its notice when a later background list read succeeds', async () => {
      seed('A', 1, 1);
      backend.invitations = [{ id: 'invite', title: 'Invited room' }];
      server.use(
        http.post('*/api/v1/chat/invitations/:id/accept', () =>
          HttpResponse.json({ error: 'failed' }, { status: 503 }),
        ),
      );
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat');
      await screen.findByText('Room A');
      fireEvent.click(
        await screen.findByRole('button', { name: /Invitations\s*1/ }),
      );
      fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
      await screen.findByText(REQUEST_FAILED);
      const socket = await dropConnection(page.socket);
      await connect(socket);
      await waitFor(() => {
        expect(readsOf(ROOMS).length).toBeGreaterThanOrEqual(2);
      });
      await settle();
      expect(screen.getByText(REQUEST_FAILED)).toBeTruthy();
    }, 30_000);
  });
  describe('extra: user write followed by a list read under a background deadline', () => {
    it('opens a newly created room without waiting out the background read deadline', async () => {
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
      backend.refusals.push({
        path: ROOMS,
        status: 429,
        headers: { 'Retry-After': '120' },
      });
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
        expect(backend.reads).toContain('POST /api/v1/chat/conversations');
      });
      await later(10_000);
      const after10s = {
        path: page.history.location.pathname,
        listReads: readsOf(ROOMS).length,
      };
      expect(after10s.path).toBe('/chat/G');
    }, 30_000);
  });

  describe('extra: late detail answer after the room was deleted', () => {
    it('does not bring back a room deleted while its detail read was on the way', async () => {
      seed('A', 1, 1);
      seed('B', 1, 1);
      const page = await loadPage();
      await connect(page.socket);
      page.open('/chat');
      await screen.findByText('Room A');
      await settle();
      const release = holdNextAnswer(/\/conversations\/A$/);
      act(() => {
        page.socket.deliver('chat.conversation_update', { id: 'A' });
      });
      await waitFor(() => {
        expect(
          backend.reads.filter((r) => r.endsWith('/conversations/A')),
        ).toHaveLength(1);
      });
      backend.rooms.delete('A');
      act(() => {
        page.socket.deliver('chat.conversation_delete', {
          conversation_id: 'A',
        });
      });
      await settle();
      const goneAfterEvent = !document.querySelector(
        '[data-conversation-id="A"]',
      );
      await release();
      await settle();
      await later(10_000);
      const back = Boolean(
        document.querySelector('[data-conversation-id="A"]'),
      );
      expect(goneAfterEvent).toBe(true);
      expect(back).toBe(false);
    }, 30_000);
  });
});
