import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import { act, cleanup, render, screen } from '@testing-library/react';
import { createMemoryHistory } from 'history';

import { IdentityContext } from 'flavours/glitch/identity_context';
import type * as InitialState from 'flavours/glitch/initial_state';

import { Chat } from '../index';
import { emitChatStreamEvent } from '../stream';

import '../testing/match_media';

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
}));
vi.mock('flavours/glitch/components/dropdown_menu', () => ({
  Dropdown: () => null,
}));
vi.mock('flavours/glitch/components/avatar', () => ({
  Avatar: () => <div className='account__avatar' />,
}));
vi.mock('flavours/glitch/components/column/header', () => ({
  ColumnHeader: () => <header />,
}));
vi.mock(
  'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container',
  () => ({ default: () => null }),
);
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const account = { id: 'me', acct: 'alice', display_name: 'Alice' };
const remote = { id: 'remote', acct: 'bob@remote.test', display_name: 'Bob' };
const waiting = (index: number) => ({
  id: `media-${index}`,
  url: `/media_proxy/${index}/original`,
  preview_url: `/media_proxy/${index}/small`,
  remote_url: `https://remote.test/files/${index}`,
  type: 'unknown',
  description: `Picture ${index}`,
  meta: null,
  blurhash: null,
});
const ready = (index: number) => ({
  ...waiting(index),
  url: `/full-${index}.png`,
  preview_url: `/small-${index}.png`,
  type: 'image',
  meta: { small: { width: 10, height: 10, aspect: 1 } },
});
const pictures = (shown: number[]) =>
  [1, 2, 3, 4].map((index) =>
    shown.includes(index) ? ready(index) : waiting(index),
  );
const incoming = (shown: number[]) => ({
  id: 'incoming',
  conversation_id: 'A',
  content: 'Four pictures',
  created_at: '2026-11-02T00:00:00Z',
  edited_at: null,
  deleted_at: null,
  reply_to_id: null,
  account: remote,
  reactions: [],
  media_attachments: pictures(shown),
});
const responses: Record<string, unknown> = {
  '/api/v1/chat/conversations': [
    {
      id: 'A',
      type: 'direct',
      title: 'Room A',
      description: null,
      unread: false,
      muted: false,
      archived: false,
      current_role: 'member',
      accounts: [account, remote],
      last_message: null,
    },
  ],
  '/api/v1/chat/invitations': [],
  '/api/v1/chat/settings': {
    policy: 'everyone',
    allow_group_invites: true,
    notifications: true,
    max_group_members: 10,
    max_attachments: 4,
    federation_enabled: true,
    delete_window_hours: 24,
    soft_delete: false,
  },
  '/api/v1/chat/conversations/A/messages': [],
};
const emit = async (event: string, payload: unknown) => {
  await act(async () => {
    emitChatStreamEvent({ event, payload });
    await Promise.resolve();
  });
};
const shownPictures = () =>
  [1, 2, 3, 4].filter((index) => screen.queryByAltText(`Picture ${index}`));
const mountOpenRoom = async () => {
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
        <Router history={createMemoryHistory({ initialEntries: ['/chat/A'] })}>
          <Route path='/chat/:conversationId?/:view?'>
            <Chat />
          </Route>
        </Router>
      </IdentityContext.Provider>
    </IntlProvider>,
  );
  await screen.findByPlaceholderText('Write a message');
  await act(async () => {
    await Promise.resolve();
  });
  await emit('chat.message', incoming([]));
  await screen.findByText('Four pictures');
  return view;
};

beforeEach(() => {
  vi.resetAllMocks();
  api.get.mockImplementation((url: string) => {
    if (url in responses) return Promise.resolve({ data: responses[url] });
    throw new Error(`Unexpected GET ${url}`);
  });
  api.post.mockResolvedValue({ data: {} });
});
afterEach(cleanup);

describe('Chat attachments from another server on an open screen', () => {
  it('shows nothing to look at until a file has arrived', async () => {
    await mountOpenRoom();

    expect(shownPictures()).toEqual([]);
  });

  it('draws each picture when its file arrives, whatever the order', async () => {
    await mountOpenRoom();

    await emit('chat.message_update', incoming([3]));
    expect(shownPictures()).toEqual([3]);

    await emit('chat.message_update', incoming([1, 3]));
    expect(shownPictures()).toEqual([1, 3]);

    await emit('chat.message_update', incoming([1, 3, 4]));
    await emit('chat.message_update', incoming([1, 2, 3, 4]));
    expect(shownPictures()).toEqual([1, 2, 3, 4]);
  });

  it('leaves a file that could not be fetched out while the rest show', async () => {
    await mountOpenRoom();

    await emit('chat.message_update', incoming([1, 2, 4]));

    expect(shownPictures()).toEqual([1, 2, 4]);
    expect(screen.getByText('Four pictures')).toBeTruthy();
  });

  it('does not call the message edited', async () => {
    await mountOpenRoom();

    await emit('chat.message_update', incoming([1, 2, 3, 4]));

    expect(shownPictures()).toEqual([1, 2, 3, 4]);
    expect(screen.queryByText('Edited')).toBeNull();
  });

  it('does not ask the server for the messages again', async () => {
    await mountOpenRoom();
    const requests = () =>
      api.get.mock.calls.filter(([url]) => String(url).endsWith('/messages'))
        .length;
    const before = requests();

    await emit('chat.message_update', incoming([1]));

    expect(requests()).toBe(before);
  });
});
