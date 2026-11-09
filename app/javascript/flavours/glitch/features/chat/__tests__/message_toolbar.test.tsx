import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { createMemoryHistory } from 'history';

import { IdentityContext } from 'flavours/glitch/identity_context';
import type * as InitialState from 'flavours/glitch/initial_state';

import { Chat } from '../index';

await vi.hoisted(() => import('../testing/match_media'));

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
  ColumnHeader: () => null,
}));
vi.mock(
  'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container',
  () => ({
    default: ({ fitToViewport }: { fitToViewport?: boolean }) => (
      <button
        type='button'
        aria-label='React'
        data-fit-viewport={fitToViewport ? 'yes' : undefined}
      />
    ),
  }),
);
vi.mock('flavours/glitch/components/media_gallery', () => ({
  default: () => <span>picture</span>,
}));
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));

const account = (id: string, displayName: string) => ({
  id,
  acct: id,
  display_name: displayName,
  avatar: `/avatars/${id}.png`,
  avatar_static: `/avatars/${id}.png`,
});
const mine = account('me', 'Alice');
const bob = account('bob', 'Bob');

const message = (id: string, content: string | null, extra: object = {}) => ({
  id,
  conversation_id: 'room',
  content,
  created_at: '2026-11-04T00:00:00Z',
  edited_at: null,
  deleted_at: null,
  reply_to_id: null,
  account: bob,
  reactions: [],
  media_attachments: [],
  editable: true,
  ...extra,
});
const fromMe = { account: mine };
const picture = {
  id: 'media-1',
  type: 'image',
  url: '/a.png',
  preview_url: '/a-small.png',
  description: null,
};
const pending = { ...picture, id: 'media-2', url: null, preview_url: null };

const mountRoom = async (list: unknown[], archived = false) => {
  const room = {
    id: 'room',
    type: 'group',
    title: 'Hikers',
    description: null,
    unread: false,
    muted: false,
    archived,
    current_role: 'member',
    accounts: [mine, bob],
    last_message: null,
  };
  api.get.mockImplementation((url: string) => {
    if (url === '/api/v1/chat/conversations')
      return Promise.resolve({ data: [room] });
    if (url === '/api/v1/chat/conversations/room')
      return Promise.resolve({ data: room });
    if (url.endsWith('/messages')) return Promise.resolve({ data: list });
    if (url === '/api/v1/chat/invitations')
      return Promise.resolve({ data: [] });
    if (url === '/api/v1/chat/settings')
      return Promise.resolve({
        data: {
          policy: 'everyone',
          allow_group_invites: true,
          notifications: true,
          max_group_members: 10,
          max_attachments: 4,
          federation_enabled: true,
          delete_window_hours: 24,
          soft_delete: false,
        },
      });
    return Promise.reject(new Error(`Unexpected GET ${url}`));
  });

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
        <Router
          history={createMemoryHistory({ initialEntries: ['/chat/room'] })}
        >
          <Route path='/chat/:conversationId?/:view?'>
            <Chat />
          </Route>
        </Router>
      </IdentityContext.Provider>
    </IntlProvider>,
  );
  await waitFor(() => {
    expect(view.container.querySelector('.chat-native__messages')).toBeTruthy();
  });
  await waitFor(() => {
    expect(view.container.querySelectorAll('article')).toHaveLength(
      list.length,
    );
  });
  return view;
};

const articleOf = (id: string) => {
  const article = document.getElementById(`chat-message-${id}`);
  if (!article) throw new Error(`Missing message ${id}`);
  return article;
};
const bubbleOf = (id: string) => {
  const bubble = articleOf(id).querySelector<HTMLElement>(
    '.chat-native__bubble',
  );
  if (!bubble) throw new Error(`Missing bubble ${id}`);
  return bubble;
};
const toolbarOf = (id: string) =>
  articleOf(id).querySelector('.chat-native__actions');
const buttonsOf = (id: string) =>
  Array.from(toolbarOf(id)?.querySelectorAll('button') ?? []).map((button) =>
    button.getAttribute('aria-label'),
  );
const copyButtonOf = (id: string) => {
  const button = toolbarOf(id)?.querySelector<HTMLButtonElement>(
    'button[aria-label="Copy"]',
  );
  if (!button) throw new Error(`Missing copy button ${id}`);
  return button;
};
const alerts = () =>
  dispatch.mock.calls
    .map(
      ([action]) =>
        (action as { payload?: { message?: { id?: string } } }).payload?.message
          ?.id,
    )
    .filter(Boolean);

const setClipboard = (clipboard: unknown) => {
  Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: clipboard,
  });
};

const writeText = vi.fn<(text: string) => Promise<void>>();

beforeEach(() => {
  vi.resetAllMocks();
  writeText.mockResolvedValue(undefined);
  setClipboard({ writeText });
  api.post.mockResolvedValue({ data: {} });
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
  setClipboard(undefined);
});

describe('Message toolbar', () => {
  it('orders the buttons of each message, ending with a named copy button only inside the toolbar, and has none on a deleted message', async () => {
    await mountRoom([
      message('1', 'Hello'),
      message('2', 'Hello', fromMe),
      message('3', 'Hello', { ...fromMe, editable: false }),
      message('4', 'Look at this', { media_attachments: [picture] }),
      message('5', null, { deleted_at: '2026-11-04T01:00:00Z' }),
    ]);

    expect(['1', '2', '3', '4'].map(buttonsOf)).toEqual([
      ['Reply', 'React', 'Copy'],
      ['Reply', 'Edit', 'Copy', 'Delete'],
      ['Reply', 'Copy', 'Delete'],
      ['Reply', 'React', 'Copy'],
    ]);
    expect(toolbarOf('5')).toBeNull();
    const react = toolbarOf('1')?.querySelector('button[aria-label="React"]');
    expect(react?.getAttribute('data-fit-viewport')).toBe('yes');
    expect(copyButtonOf('1').getAttribute('title')).toBe('Copy');
    expect(copyButtonOf('1').getAttribute('aria-label')).toBe('Copy');
    const copies = screen.getAllByRole('button', { name: 'Copy' });
    expect(copies).toHaveLength(4);
    copies.forEach((button) => {
      expect(button.closest('.chat-native__actions')).toBeTruthy();
    });
  });

  it('offers no copy on a message with no, empty or only blank text', async () => {
    const contents = [null, '', ' \n '];
    await mountRoom(
      contents.flatMap((content, index) => [
        message(`other-${index}`, content, { media_attachments: [picture] }),
        message(`mine-${index}`, content, {
          ...fromMe,
          media_attachments: [picture],
        }),
      ]),
    );

    expect(
      contents.map((_content, index) => [
        buttonsOf(`other-${index}`),
        buttonsOf(`mine-${index}`),
      ]),
    ).toEqual(
      contents.map(() => [
        ['Reply', 'React'],
        ['Reply', 'Edit', 'Delete'],
      ]),
    );
  });
});

describe('Copying a message', () => {
  it('copies the body exactly as shown', async () => {
    const body = 'First line\n  second  line\n\nlast ';
    await mountRoom([message('1', body)]);

    fireEvent.click(copyButtonOf('1'));

    expect(writeText).toHaveBeenCalledTimes(1);
    expect(writeText).toHaveBeenCalledWith(body);
    await waitFor(() => {
      expect(alerts()).toEqual(['copy_icon_button.copied']);
    });
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('leaves the quoted message out of a reply', async () => {
    await mountRoom([
      message('1', 'The original'),
      message('2', 'My answer', { ...fromMe, reply_to_id: '1' }),
    ]);
    expect(bubbleOf('2').textContent).toContain('The original');

    fireEvent.click(copyButtonOf('2'));

    expect(writeText).toHaveBeenCalledWith('My answer');
  });

  it('does not say it was copied when writing fails, and clears the failure once a copy works', async () => {
    writeText.mockRejectedValueOnce(new Error('NotAllowedError'));
    await mountRoom([message('1', 'Hello')]);

    fireEvent.click(copyButtonOf('1'));

    expect((await screen.findByRole('alert')).textContent).toBe(
      'The message could not be copied.',
    );
    expect(alerts()).toEqual([]);

    fireEvent.click(copyButtonOf('1'));

    await waitFor(() => {
      expect(alerts()).toEqual(['copy_icon_button.copied']);
    });
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('does not say it was copied when the browser has no clipboard', async () => {
    setClipboard(undefined);
    await mountRoom([message('1', 'Hello')]);

    fireEvent.click(copyButtonOf('1'));

    expect((await screen.findByRole('alert')).textContent).toBe(
      'The message could not be copied.',
    );
    expect(alerts()).toEqual([]);
  });
});

describe('Archived room', () => {
  it('shows only the copy button, on anyone’s message with text, and still copies', async () => {
    await mountRoom(
      [
        message('1', 'From Bob'),
        message('2', 'From me', fromMe),
        message('3', null, { media_attachments: [picture] }),
        message('4', null, { deleted_at: '2026-11-04T01:00:00Z' }),
      ],
      true,
    );

    expect(buttonsOf('1')).toEqual(['Copy']);
    expect(buttonsOf('2')).toEqual(['Copy']);
    expect(toolbarOf('3')).toBeNull();
    expect(toolbarOf('4')).toBeNull();

    fireEvent.click(copyButtonOf('1'));

    expect(writeText).toHaveBeenCalledWith('From Bob');
    await waitFor(() => {
      expect(alerts()).toEqual(['copy_icon_button.copied']);
    });
  });
});

describe('Long press on a message', () => {
  const finger = (x = 10, y = 10) => ({
    touches: [{ identifier: 1, clientX: x, clientY: y }],
    changedTouches: [{ identifier: 1, clientX: x, clientY: y }],
  });
  const textOf = (id: string) => {
    const text = bubbleOf(id).querySelector('p');
    if (!text) throw new Error(`Missing text ${id}`);
    return text;
  };
  const wait = (ms: number) => {
    act(() => {
      vi.advanceTimersByTime(ms);
    });
  };
  const mountForTouch = async (list: unknown[]) => {
    const view = await mountRoom(list);
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    return view;
  };

  it('keeps Safari from focusing the bubble before a touched quote receives its click', async () => {
    await mountForTouch([
      message('1', 'The original'),
      message('2', 'Reply', { reply_to_id: '1' }),
    ]);
    const quote = bubbleOf('2').querySelector(
      '.chat-native__reply-quote strong',
    );
    if (!quote) throw new Error('Missing quote');
    const composer = document.querySelector<HTMLTextAreaElement>(
      '.chat-native__composer textarea',
    );
    if (!composer) throw new Error('Missing composer');
    composer.focus();

    fireEvent.touchStart(quote, finger(103, 63));
    wait(57);
    fireEvent.touchEnd(quote, { touches: [] });
    expect(fireEvent.mouseDown(quote)).toBe(false);
    expect(document.activeElement).not.toBe(composer);
    expect(fireEvent.click(quote)).toBe(true);
  });

  it('leaves an ordinary mouse press, bubble text, and a quote touch that turns into a scroll alone', async () => {
    await mountForTouch([
      message('1', 'The original'),
      message('2', 'Reply', { reply_to_id: '1' }),
    ]);
    const quote = bubbleOf('2').querySelector(
      '.chat-native__reply-quote strong',
    );
    if (!quote) throw new Error('Missing quote');
    expect(fireEvent.mouseDown(quote)).toBe(true);
    fireEvent.touchStart(textOf('2'), finger());
    fireEvent.touchEnd(textOf('2'), { touches: [] });
    expect(fireEvent.mouseDown(textOf('2'))).toBe(true);

    fireEvent.touchStart(quote, finger(103, 100));
    fireEvent.touchMove(quote, finger(103, 89));
    fireEvent.touchEnd(quote, { touches: [] });
    expect(fireEvent.mouseDown(quote)).toBe(true);
  });

  it('keeps a long-pressed quote marked when the browser focuses it, until the next touch', async () => {
    await mountForTouch([
      message('1', 'The original'),
      message('2', 'Reply', { reply_to_id: '1' }),
    ]);
    const quote = bubbleOf('2').querySelector<HTMLButtonElement>(
      '.chat-native__reply-quote',
    );
    if (!quote) throw new Error('Missing quote');
    fireEvent.touchStart(quote, finger(119, 306));
    wait(500);
    expect(document.activeElement).toBe(bubbleOf('2'));
    quote.focus();
    fireEvent.touchEnd(quote, { touches: [] });
    expect(bubbleOf('2').matches('[data-chat-long-pressed]:focus-within')).toBe(
      true,
    );
    const action = toolbarOf('2')?.querySelector('button');
    if (!action) throw new Error('Missing toolbar button');
    fireEvent.touchStart(action, finger(119, 280));
    fireEvent.touchEnd(action, { touches: [] });
    fireEvent.mouseDown(action);
    expect(bubbleOf('2').hasAttribute('data-chat-long-pressed')).toBe(true);
    fireEvent.touchStart(quote, finger(119, 306));
    expect(bubbleOf('2').hasAttribute('data-chat-long-pressed')).toBe(false);
  });

  it('opens the toolbar by focusing the bubble without scrolling, before the finger lifts', async () => {
    await mountForTouch([message('1', 'Hello')]);
    const focus = vi.spyOn(bubbleOf('1'), 'focus');

    fireEvent.touchStart(textOf('1'), finger());
    wait(499);
    expect(document.activeElement).not.toBe(bubbleOf('1'));
    wait(1);

    expect(document.activeElement).toBe(bubbleOf('1'));
    expect(toolbarOf('1')?.closest('article')?.matches(':focus-within')).toBe(
      true,
    );
    expect(focus).toHaveBeenCalledWith({ preventScroll: true });
    fireEvent.touchEnd(textOf('1'), { touches: [] });
    expect(document.activeElement).toBe(bubbleOf('1'));
  });

  it('stays closed after a short tap, a scrolling finger, a browser takeover, or a second finger', async () => {
    await mountForTouch([message('1', 'Hello')]);
    const two = {
      touches: [
        { identifier: 1, clientX: 10, clientY: 10 },
        { identifier: 2, clientX: 50, clientY: 50 },
      ],
    };

    fireEvent.touchStart(textOf('1'), finger());
    wait(100);
    fireEvent.touchEnd(textOf('1'), { touches: [] });
    wait(1000);
    expect(document.activeElement).not.toBe(bubbleOf('1'));

    fireEvent.touchStart(textOf('1'), finger(10, 100));
    wait(100);
    fireEvent.touchMove(textOf('1'), finger(10, 89));
    wait(1000);
    expect(document.activeElement).not.toBe(bubbleOf('1'));

    fireEvent.touchStart(textOf('1'), finger());
    fireEvent.touchCancel(textOf('1'), { touches: [] });
    wait(1000);
    expect(document.activeElement).not.toBe(bubbleOf('1'));

    fireEvent.touchStart(textOf('1'), finger());
    fireEvent.touchStart(textOf('1'), two);
    wait(1000);
    expect(document.activeElement).not.toBe(bubbleOf('1'));
  });

  it('forgives the small movement of a resting finger', async () => {
    await mountForTouch([message('1', 'Hello')]);

    fireEvent.touchStart(textOf('1'), finger(10, 100));
    fireEvent.touchMove(textOf('1'), finger(13, 94));
    wait(500);

    expect(document.activeElement).toBe(bubbleOf('1'));
  });

  it('leaves a picture or another attachment in the bubble to the browser', async () => {
    const { container } = await mountForTouch([
      message('1', 'Look', { media_attachments: [picture] }),
      message('2', 'Look', { media_attachments: [pending] }),
    ]);
    const gallery = container.querySelector('.chat-native__gallery');
    if (!gallery) throw new Error('Missing gallery');
    const attachment = container.querySelector('.chat-native__attachment');
    if (!attachment) throw new Error('Missing attachment');

    fireEvent.touchStart(gallery, finger());
    wait(1000);
    expect(document.activeElement).not.toBe(bubbleOf('1'));

    fireEvent.touchStart(attachment, finger());
    wait(1000);
    expect(document.activeElement).not.toBe(bubbleOf('2'));
  });

  it('does nothing once the screen has gone', async () => {
    const { unmount } = await mountForTouch([message('1', 'Hello')]);
    const bubble = bubbleOf('1');
    const focus = vi.spyOn(bubble, 'focus');

    fireEvent.touchStart(textOf('1'), finger());
    unmount();
    vi.advanceTimersByTime(1000);

    expect(focus).not.toHaveBeenCalled();
  });
});
