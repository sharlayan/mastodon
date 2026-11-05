import { IntlProvider } from 'react-intl';

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
const dispatch = vi.hoisted(() => vi.fn());
vi.mock('flavours/glitch/api', () => ({ default: () => api }));
vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<typeof InitialState>()),
  me: 'me',
}));
vi.mock('flavours/glitch/store', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  useAppDispatch: () => dispatch,
  useAppSelector: () => false,
}));
vi.mock('flavours/glitch/components/dropdown_menu', () => ({
  Dropdown: () => null,
}));
vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: ({ title }: { title?: React.ReactNode }) => (
    <header>
      <h1>{title}</h1>
    </header>
  ),
}));
vi.mock(
  'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container',
  () => ({ default: () => null }),
);
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const account = (id: string, displayName: string, domain?: string) => ({
  id,
  acct: domain ? `${id}@${domain}` : id,
  display_name: displayName,
  avatar: `/avatars/${id}.png`,
  avatar_static: `/avatars/${id}.png`,
});
const mine = account('me', 'Alice');
const cherryNari = { ...account('nari', 'Nari', 'cherry.test'), id: 'nari-1' };
const otherNari = { ...account('nari', 'Nari', 'other.test'), id: 'nari-2' };
const bob = account('bob', 'Bob');
const carol = account('carol', 'Carol', 'cherry.test');
const unnamed = account('plain', '', 'cherry.test');

const room = (
  id: string,
  type: 'direct' | 'group',
  others: unknown[],
  extra: object = {},
) => ({
  id,
  type,
  title: null,
  description: null,
  unread: false,
  muted: false,
  archived: false,
  current_role: 'member',
  accounts: [mine, ...others],
  last_message: null,
  ...extra,
});
const directNari = room('direct-1', 'direct', [cherryNari]);
const directOtherNari = room('direct-2', 'direct', [otherNari]);
const directUnnamed = room('direct-3', 'direct', [unnamed]);
const hikers = room('group-1', 'group', [bob], {
  title: 'Hikers',
  current_role: 'owner',
});
const readers = room('group-2', 'group', [bob], { title: 'Readers' });
const myMessage = {
  id: 'mine-1',
  conversation_id: 'direct-1',
  content: 'What I wrote',
  created_at: '2026-11-04T00:00:00Z',
  edited_at: null,
  deleted_at: null,
  reply_to_id: null,
  account: mine,
  reactions: [],
  media_attachments: [],
  editable: true,
};
const invitationTo = (invitee: unknown, id = 'sent-1') => ({
  id,
  state: 'pending',
  conversation: hikers,
  inviter: mine,
  invitee,
});

let sentInvitations: unknown[] = [];
let received: unknown[] = [];

const responses = (
  url: string,
  config?: { params?: { direction?: string } },
) => {
  if (url === '/api/v1/chat/conversations')
    return [directNari, directOtherNari, directUnnamed, hikers, readers];
  if (url === '/api/v1/chat/invitations')
    return config?.params?.direction === 'sent' ? sentInvitations : received;
  if (url === '/api/v1/chat/settings')
    return {
      policy: 'everyone',
      allow_group_invites: true,
      notifications: true,
      max_group_members: 10,
      max_attachments: 4,
      federation_enabled: true,
      delete_window_hours: 24,
      soft_delete: false,
    };
  if (url.endsWith('/messages'))
    return url.includes('direct-1') ? [myMessage] : [];
  const single = [directNari, hikers, readers].find((item) =>
    url.endsWith(`/conversations/${item.id}`),
  );
  if (single) return single;
  throw new Error(`Unexpected GET ${url}`);
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

const composer = () =>
  screen.getByPlaceholderText<HTMLTextAreaElement>('Write a message');
const sendButton = () => screen.getByRole('button', { name: 'Send' });
const chooseFile = (container: HTMLElement) => {
  const input = container.querySelector('input[type="file"]');
  if (!input) throw new Error('Missing attachment input');
  fireEvent.change(input, {
    target: { files: [new File(['x'], 'a.png', { type: 'image/png' })] },
  });
};
const alerted = () =>
  dispatch.mock.calls.map(
    ([action]) =>
      (
        action as {
          payload?: { message?: { id?: string }; values?: unknown };
        }
      ).payload,
  );

beforeEach(() => {
  vi.resetAllMocks();
  sentInvitations = [];
  received = [];
  api.get.mockImplementation(
    (url: string, config?: { params?: { direction?: string } }) =>
      Promise.resolve({ data: responses(url, config) }),
  );
  api.post.mockResolvedValue({ data: {} });
  api.delete.mockResolvedValue({ data: {} });
});
afterEach(cleanup);

describe('Pressing Send with the message box in use', () => {
  const mountRoom = async () => {
    const view = mountAt('/chat/direct-1');
    await screen.findByText('What I wrote');
    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: 'Attach media' }),
      ).toHaveProperty('disabled', false);
    });
    return view;
  };
  const holdSend = () => {
    let answer: () => void = () => undefined;
    api.post.mockImplementation(
      () =>
        new Promise((resolve) => {
          answer = () => {
            resolve({ data: { ...myMessage, id: 'sent' } });
          };
        }),
    );
    return () => {
      answer();
    };
  };
  const formOf = (container: HTMLElement) => {
    const form = container.querySelector<HTMLElement>(
      'form.chat-native__composer',
    );
    if (!form) throw new Error('Missing composer');
    return form;
  };
  // fireEvent answers false when the page has stopped what the browser would do: here, moving the focus.
  const movesFocus = (element: HTMLElement) => fireEvent.mouseDown(element);

  it('keeps the focus in the box', async () => {
    await mountRoom();
    fireEvent.change(composer(), { target: { value: 'Going out' } });
    composer().focus();

    expect(movesFocus(sendButton())).toBe(false);
  });

  it('keeps the focus in the box when the button is disabled', async () => {
    const { container } = await mountRoom();
    composer().focus();

    // A disabled button lets the press through to the form behind it.
    expect(movesFocus(formOf(container))).toBe(false);
  });

  it('does not touch the focus when the box does not have it', async () => {
    const { container } = await mountRoom();
    fireEvent.change(composer(), { target: { value: 'Going out' } });

    expect(movesFocus(sendButton())).toBe(true);
    expect(movesFocus(formOf(container))).toBe(true);
    expect(document.activeElement).not.toBe(composer());
  });

  it('leaves the other controls of the composer alone', async () => {
    await mountRoom();
    composer().focus();

    expect(
      movesFocus(screen.getByRole('button', { name: 'Attach media' })),
    ).toBe(true);
    expect(movesFocus(composer())).toBe(true);
  });

  it('keeps the box writable while the message is on its way', async () => {
    const answer = holdSend();
    await mountRoom();
    fireEvent.change(composer(), { target: { value: 'Going out' } });

    fireEvent.click(sendButton());

    await waitFor(() => {
      expect(api.post).toHaveBeenCalled();
    });
    expect(composer().readOnly).toBe(false);
    await act(async () => {
      answer();
      await Promise.resolve();
    });
  });

  it('keeps what is typed while the message is on its way', async () => {
    const answer = holdSend();
    await mountRoom();
    fireEvent.change(composer(), { target: { value: 'Going out' } });

    fireEvent.click(sendButton());
    await waitFor(() => {
      expect(api.post).toHaveBeenCalled();
    });
    fireEvent.change(composer(), { target: { value: 'Going out and more' } });
    await act(async () => {
      answer();
      await Promise.resolve();
    });

    await waitFor(() => {
      expect(composer().value).toBe(' and more');
    });
  });

  it('keeps a box rewritten while the message is on its way', async () => {
    const answer = holdSend();
    await mountRoom();
    fireEvent.change(composer(), { target: { value: 'Going out' } });

    fireEvent.click(sendButton());
    await waitFor(() => {
      expect(api.post).toHaveBeenCalled();
    });
    fireEvent.change(composer(), { target: { value: 'Something else' } });
    await act(async () => {
      answer();
      await Promise.resolve();
    });

    await waitFor(() => {
      expect(document.getElementById('chat-message-sent')).toBeTruthy();
    });
    expect(composer().value).toBe('Something else');
  });
});

describe('Home and End in the message box', () => {
  const MAC =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';
  const WINDOWS =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';
  const mountOn = async (userAgent: string) => {
    vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(userAgent);
    mountAt('/chat/direct-1');
    await screen.findByText('What I wrote');
  };
  const shape = (
    scrollTop: number,
    clientHeight: number,
    scrollHeight: number,
  ) => {
    const box = composer();
    Object.defineProperties(box, {
      scrollTop: { configurable: true, value: scrollTop },
      clientHeight: { configurable: true, value: clientHeight },
      scrollHeight: { configurable: true, value: scrollHeight },
    });
    return box;
  };
  // fireEvent answers false when the page has stopped what the browser would do.
  const leftToBrowser = (box: HTMLElement, init: object) =>
    fireEvent.keyDown(box, init);

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it.each(['Home', 'End'])(
    'keeps %s from moving the conversation on a Mac',
    async (key) => {
      await mountOn(MAC);

      expect(leftToBrowser(shape(0, 44, 44), { key })).toBe(false);
    },
  );

  it('leaves End to the box while it still has more to scroll', async () => {
    await mountOn(MAC);

    expect(leftToBrowser(shape(0, 44, 300), { key: 'End' })).toBe(true);
    expect(leftToBrowser(shape(256, 44, 300), { key: 'End' })).toBe(false);
  });

  it('leaves Home to the box while it still has more to scroll', async () => {
    await mountOn(MAC);

    expect(leftToBrowser(shape(100, 44, 300), { key: 'Home' })).toBe(true);
    expect(leftToBrowser(shape(0, 44, 300), { key: 'Home' })).toBe(false);
  });

  it.each([
    { shiftKey: true },
    { metaKey: true },
    { ctrlKey: true },
    { altKey: true },
  ])('leaves End with a modifier alone on a Mac: %o', async (modifier) => {
    await mountOn(MAC);

    expect(leftToBrowser(shape(0, 44, 44), { key: 'End', ...modifier })).toBe(
      true,
    );
  });

  it.each(['PageUp', 'PageDown', 'ArrowLeft'])(
    'leaves %s alone on a Mac',
    async (key) => {
      await mountOn(MAC);

      expect(leftToBrowser(shape(0, 44, 44), { key })).toBe(true);
    },
  );

  it.each(['Home', 'End'])(
    'leaves %s moving the caret on other systems',
    async (key) => {
      await mountOn(WINDOWS);

      expect(leftToBrowser(shape(0, 44, 44), { key })).toBe(true);
    },
  );
});

describe('Typing while an attachment uploads', () => {
  const holdUpload = () => {
    let finish: () => void = () => undefined;
    api.post.mockImplementation((url: string) =>
      url === '/api/v2/media'
        ? new Promise((resolve) => {
            finish = () => {
              resolve({
                data: {
                  id: 'media-1',
                  url: '/a.png',
                  preview_url: '/a-small.png',
                  type: 'image',
                  description: null,
                },
              });
            };
          })
        : Promise.resolve({ data: { ...myMessage, id: 'sent' } }),
    );
    return () => {
      finish();
    };
  };

  it('keeps what is typed during the upload, and sends both together', async () => {
    const finish = holdUpload();
    const { container } = mountAt('/chat/direct-1');
    await screen.findByText('What I wrote');
    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: 'Attach media' }),
      ).toHaveProperty('disabled', false);
    });

    chooseFile(container);
    await waitFor(() => {
      expect(api.post).toHaveBeenCalledWith(
        '/api/v2/media',
        expect.any(FormData),
      );
    });

    expect(composer().readOnly).toBe(false);
    fireEvent.change(composer(), { target: { value: 'Typed meanwhile' } });
    expect(composer().value).toBe('Typed meanwhile');

    await act(async () => {
      finish();
      await Promise.resolve();
    });
    await screen.findByRole('button', { name: 'Remove attachment' });
    expect(composer().value).toBe('Typed meanwhile');

    fireEvent.click(sendButton());
    await waitFor(() => {
      expect(api.post).toHaveBeenCalledWith(
        '/api/v1/chat/conversations/direct-1/messages',
        expect.objectContaining({
          text: 'Typed meanwhile',
          media_ids: ['media-1'],
        }),
      );
    });
  });

  it('does not send until the upload has finished', async () => {
    const finish = holdUpload();
    const { container } = mountAt('/chat/direct-1');
    await screen.findByText('What I wrote');
    await waitFor(() => {
      expect(
        screen.getByRole('button', { name: 'Attach media' }),
      ).toHaveProperty('disabled', false);
    });

    chooseFile(container);
    fireEvent.change(composer(), { target: { value: 'Too soon' } });
    await waitFor(() => {
      expect(sendButton()).toHaveProperty('disabled', true);
    });

    fireEvent.keyDown(composer(), { key: 'Enter', code: 'Enter' });
    expect(api.post).not.toHaveBeenCalledWith(
      '/api/v1/chat/conversations/direct-1/messages',
      expect.anything(),
    );
    expect(screen.getByRole('button', { name: 'Attach media' })).toHaveProperty(
      'disabled',
      true,
    );

    await act(async () => {
      finish();
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(sendButton()).toHaveProperty('disabled', false);
    });
  });

  it('empties the box once the message has gone', async () => {
    let answer: () => void = () => undefined;
    api.post.mockImplementation(
      () =>
        new Promise((resolve) => {
          answer = () => {
            resolve({ data: { ...myMessage, id: 'sent' } });
          };
        }),
    );
    mountAt('/chat/direct-1');
    await screen.findByText('What I wrote');
    fireEvent.change(composer(), { target: { value: 'Going out' } });

    fireEvent.click(sendButton());

    await waitFor(() => {
      expect(api.post).toHaveBeenCalled();
    });
    expect(composer().readOnly).toBe(false);
    await act(async () => {
      answer();
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(composer().value).toBe('');
    });
    expect(composer().readOnly).toBe(false);
  });
});

describe('Telling apart people with the same name', () => {
  const rowOf = (acct: string) =>
    screen.getByText(`@${acct}`).closest('button') as HTMLElement;

  it('shows the address beside the name of a direct chat in the list', async () => {
    mountAt('/chat');
    await screen.findByText('@nari@cherry.test');

    expect(within(rowOf('nari@cherry.test')).getByText('Nari')).toBeTruthy();
    expect(within(rowOf('nari@other.test')).getByText('Nari')).toBeTruthy();
    expect(rowOf('nari@cherry.test')).not.toBe(rowOf('nari@other.test'));
  });

  it('keeps the full address within reach when it is cut off', async () => {
    mountAt('/chat');
    await screen.findByText('@nari@cherry.test');

    expect(
      rowOf('nari@cherry.test').querySelector('[title="@nari@cherry.test"]'),
    ).toBeTruthy();
  });

  it('does not show the address twice when there is no display name', async () => {
    mountAt('/chat');
    const name = await screen.findByText('plain@cherry.test');

    expect(name.closest('button')?.textContent).toBe('plain@cherry.test');
  });

  it('keeps the full address within reach in search results and selected accounts', async () => {
    api.get.mockImplementation(
      (url: string, config?: { params?: { direction?: string } }) =>
        url === '/api/v2/search'
          ? Promise.resolve({ data: { accounts: [carol] } })
          : Promise.resolve({ data: responses(url, config) }),
    );
    mountAt('/chat/new');
    fireEvent.change(
      await screen.findByPlaceholderText('Search for an account'),
      { target: { value: 'carol' } },
    );

    const address = await screen.findByText('@carol@cherry.test');
    expect(address.getAttribute('title')).toBe('@carol@cherry.test');

    fireEvent.click(address.closest('button') as HTMLElement);

    expect(screen.getByText('@carol@cherry.test').getAttribute('title')).toBe(
      '@carol@cherry.test',
    );
  });

  it('keeps the full address within reach for members and people invited', async () => {
    sentInvitations = [invitationTo(carol)];
    mountAt('/chat/group-1/members');

    expect(
      (await screen.findByText('@carol@cherry.test')).getAttribute('title'),
    ).toBe('@carol@cherry.test');
    expect(screen.getByText('@bob').getAttribute('title')).toBe('@bob');
  });

  it('leaves a group as its name', async () => {
    mountAt('/chat');
    fireEvent.click(await screen.findByRole('button', { name: 'Your groups' }));
    const name = await screen.findByText('Hikers');

    expect(name.closest('button')?.textContent).toBe('Hikers');
  });

  it('shows name and address as the title of a direct chat, linked to the profile', async () => {
    mountAt('/chat/direct-1');
    await screen.findByText('What I wrote');
    const heading = screen.getByRole('heading', { level: 1 });

    expect(within(heading).getByText('Nari')).toBeTruthy();
    const address = within(heading).getByText('@nari@cherry.test');
    expect(address.getAttribute('title')).toBe('@nari@cherry.test');
    expect(address.closest('a')?.getAttribute('href')).toBe(
      '/@nari@cherry.test',
    );
  });

  it('leaves the title of a group as its name', async () => {
    mountAt('/chat/group-2');
    await screen.findByPlaceholderText('Write a message');

    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe(
      'Readers',
    );
  });
});

describe('People who have not answered an invitation', () => {
  const openMembers = async () => {
    mountAt('/chat/group-1/members');
    await screen.findByText('@bob');
  };

  it('shows them apart from the members, for the owner', async () => {
    sentInvitations = [invitationTo(carol)];

    await openMembers();

    const row = (await screen.findByText('Carol')).closest(
      '.chat-native__member',
    ) as HTMLElement;
    expect(within(row).getByText('Invited')).toBeTruthy();
    expect(within(row).getByText('@carol@cherry.test')).toBeTruthy();
    expect(row.querySelector('.account__avatar img')).toBeTruthy();
    expect(api.get).toHaveBeenCalledWith('/api/v1/chat/invitations', {
      params: { direction: 'sent', conversation_id: 'group-1' },
    });
    const bobRow = screen.getByText('@bob').closest('.chat-native__member');
    expect(bobRow?.textContent).not.toContain('Invited');
  });

  it('lists them in the order they were invited, after the members', async () => {
    // The API gives the newest first.
    sentInvitations = [
      invitationTo(unnamed, 'sent-2'),
      invitationTo(carol, 'sent-1'),
    ];

    await openMembers();
    await screen.findByText('Carol');

    expect(
      Array.from(document.querySelectorAll('.chat-native__member strong')).map(
        (name) => name.textContent,
      ),
    ).toEqual(['Alice', 'Bob', 'Carol', 'plain@cherry.test']);
  });

  it('lets the owner cancel one, and says so', async () => {
    sentInvitations = [invitationTo(carol)];
    await openMembers();
    await screen.findByText('Carol');

    fireEvent.click(screen.getByRole('button', { name: 'Cancel invitation' }));

    await waitFor(() => {
      expect(api.delete).toHaveBeenCalledWith(
        '/api/v1/chat/invitations/sent-1',
      );
    });
    await waitFor(() => {
      expect(screen.queryByText('Carol')).toBeNull();
    });
    expect(alerted()).toContainEqual(
      expect.objectContaining({
        message: expect.objectContaining({
          id: 'chat.invitation_cancelled',
        }) as unknown,
        values: { account: 'Carol' },
      }),
    );
  });

  it('keeps the row and shows an error when cancelling fails', async () => {
    sentInvitations = [invitationTo(carol)];
    api.delete.mockRejectedValue(new Error('no'));
    await openMembers();
    await screen.findByText('Carol');

    fireEvent.click(screen.getByRole('button', { name: 'Cancel invitation' }));

    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(screen.getByText('Carol')).toBeTruthy();
  });

  it('lists the person just invited without leaving the screen', async () => {
    api.get.mockImplementation(
      (url: string, config?: { params?: { direction?: string } }) =>
        url === '/api/v2/search'
          ? Promise.resolve({ data: { accounts: [carol] } })
          : Promise.resolve({ data: responses(url, config) }),
    );
    api.post.mockImplementation(() => {
      sentInvitations = [invitationTo(carol)];
      return Promise.resolve({ data: invitationTo(carol) });
    });
    await openMembers();

    fireEvent.change(screen.getByPlaceholderText('Search for an account'), {
      target: { value: 'carol' },
    });
    fireEvent.click(await screen.findByRole('button', { name: /Carol/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Invite' }));

    expect(await screen.findByText('Invited')).toBeTruthy();
  });

  it('updates an open screen when someone answers', async () => {
    sentInvitations = [invitationTo(carol)];
    await openMembers();
    await screen.findByText('Carol');

    sentInvitations = [];
    await act(async () => {
      emitChatStreamEvent({
        event: 'chat.invitation_update',
        payload: { conversation_id: 'group-1' },
      });
      await Promise.resolve();
    });

    await waitFor(() => {
      expect(screen.queryByText('Carol')).toBeNull();
    });
  });

  it('ignores an answer about another group', async () => {
    sentInvitations = [invitationTo(carol)];
    await openMembers();
    await screen.findByText('Carol');
    const requests = () =>
      api.get.mock.calls.filter(
        ([url, config]) =>
          url === '/api/v1/chat/invitations' &&
          (config as { params?: { direction?: string } } | undefined)?.params
            ?.direction === 'sent',
      ).length;
    const before = requests();

    await act(async () => {
      emitChatStreamEvent({
        event: 'chat.invitation_update',
        payload: { conversation_id: 'group-2' },
      });
      await Promise.resolve();
    });

    expect(requests()).toBe(before);
  });

  it('moves someone who accepted into the member count and list on an open screen', async () => {
    sentInvitations = [invitationTo(carol)];
    await openMembers();
    await screen.findByText('Carol');

    sentInvitations = [];
    await act(async () => {
      emitChatStreamEvent({
        event: 'chat.conversation_update',
        payload: { ...hikers, accounts: [mine, bob, carol] },
      });
      emitChatStreamEvent({
        event: 'chat.invitation_update',
        payload: { conversation_id: 'group-1' },
      });
      await Promise.resolve();
    });

    await waitFor(() => {
      expect(screen.queryByText('Invited')).toBeNull();
    });
    expect(
      screen.getByText('Carol').closest('.chat-native__member'),
    ).toBeTruthy();
  });

  it('asks nothing and shows nothing for a member who is not the owner', async () => {
    mountAt('/chat/group-2/members');
    await screen.findByText('@bob');

    expect(screen.queryByText('Invited')).toBeNull();
    expect(api.get).not.toHaveBeenCalledWith(
      '/api/v1/chat/invitations',
      expect.objectContaining({
        params: expect.objectContaining({ direction: 'sent' }) as unknown,
      }),
    );
  });
});

describe('Answering an invitation', () => {
  const invitation = {
    id: 'inv-1',
    state: 'pending',
    conversation: room('invited', 'group', [carol], { title: 'Book club' }),
    inviter: carol,
  };
  const openInvitations = async () => {
    received = [invitation];
    mountAt('/chat');
    fireEvent.click(
      await screen.findByRole('button', { name: /Invitations\s*1/ }),
    );
    await screen.findByText('Book club');
  };

  it('says what each button does, in words', async () => {
    await openInvitations();

    expect(screen.getByRole('button', { name: 'Accept' }).textContent).toBe(
      'Accept',
    );
    expect(screen.getByRole('button', { name: 'Reject' }).textContent).toBe(
      'Reject',
    );
  });

  it.each([
    ['Accept', 'chat.invitation_accepted'],
    ['Reject', 'chat.invitation_rejected'],
  ])('reports the result of %s', async (name, id) => {
    await openInvitations();

    fireEvent.click(screen.getByRole('button', { name }));

    await waitFor(() => {
      expect(alerted()).toContainEqual(
        expect.objectContaining({
          message: expect.objectContaining({ id }) as unknown,
          values: { group: 'Book club' },
        }),
      );
    });
    expect(screen.queryByText('Book club')).toBeNull();
  });

  it('reports no result when answering fails', async () => {
    api.post.mockRejectedValue(new Error('no'));
    await openInvitations();

    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));

    expect(await screen.findByRole('alert')).toBeTruthy();
    expect(alerted()).toEqual([]);
    expect(screen.getByText('Book club')).toBeTruthy();
  });
});

describe('The send button while editing', () => {
  it('says save while editing and send again after cancelling', async () => {
    mountAt('/chat/direct-1');
    await screen.findByText('What I wrote');
    expect(sendButton()).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));

    expect(screen.getByRole('button', { name: 'Save' })).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Send' })).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(sendButton()).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Save' })).toBeNull();
  });
});
