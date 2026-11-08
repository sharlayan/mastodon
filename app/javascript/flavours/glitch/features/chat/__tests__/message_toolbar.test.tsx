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
  it('ends with the copy button on a message from someone else', async () => {
    await mountRoom([message('1', 'Hello')]);

    expect(buttonsOf('1')).toEqual(['Reply', 'React', 'Copy']);
  });

  // On a short phone screen the picker opened beside a message in the middle ran off the bottom of the screen.
  it('asks the reaction picker to stay on the screen', async () => {
    await mountRoom([message('1', 'Hello')]);

    const react = toolbarOf('1')?.querySelector('button[aria-label="React"]');
    expect(react?.getAttribute('data-fit-viewport')).toBe('yes');
  });

  it('keeps delete last on my own message', async () => {
    await mountRoom([message('1', 'Hello', fromMe)]);

    expect(buttonsOf('1')).toEqual(['Reply', 'Edit', 'Copy', 'Delete']);
  });

  it('offers copy on my message that can no longer be edited', async () => {
    await mountRoom([message('1', 'Hello', { ...fromMe, editable: false })]);

    expect(buttonsOf('1')).toEqual(['Reply', 'Copy', 'Delete']);
  });

  it('names the copy button for both pointer and screen reader', async () => {
    await mountRoom([message('1', 'Hello')]);

    expect(copyButtonOf('1').getAttribute('title')).toBe('Copy');
    expect(copyButtonOf('1').getAttribute('aria-label')).toBe('Copy');
  });

  it('only ever shows the copy button inside the toolbar', async () => {
    await mountRoom([message('1', 'Hello'), message('2', 'Hi', fromMe)]);

    const copies = screen.getAllByRole('button', { name: 'Copy' });
    expect(copies).toHaveLength(2);
    copies.forEach((button) => {
      expect(button.closest('.chat-native__actions')).toBeTruthy();
    });
  });

  it.each([
    ['no text', null],
    ['empty text', ''],
    ['only blank text', ' \n '],
  ])('offers no copy on a message with %s', async (_name, content) => {
    await mountRoom([
      message('1', content, { media_attachments: [picture] }),
      message('2', content, { ...fromMe, media_attachments: [picture] }),
    ]);

    expect(buttonsOf('1')).toEqual(['Reply', 'React']);
    expect(buttonsOf('2')).toEqual(['Reply', 'Edit', 'Delete']);
  });

  it('offers copy on a message with both a picture and text', async () => {
    await mountRoom([
      message('1', 'Look at this', { media_attachments: [picture] }),
    ]);

    expect(buttonsOf('1')).toContain('Copy');
  });

  it('has no toolbar on a deleted message', async () => {
    await mountRoom([
      message('1', null, { deleted_at: '2026-11-04T01:00:00Z' }),
    ]);

    expect(toolbarOf('1')).toBeNull();
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

  it('does not say it was copied when writing fails', async () => {
    writeText.mockRejectedValue(new Error('NotAllowedError'));
    await mountRoom([message('1', 'Hello')]);

    fireEvent.click(copyButtonOf('1'));

    expect((await screen.findByRole('alert')).textContent).toBe(
      'The message could not be copied.',
    );
    expect(alerts()).toEqual([]);
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

  it('clears the failure once a copy works', async () => {
    writeText.mockRejectedValueOnce(new Error('NotAllowedError'));
    await mountRoom([message('1', 'Hello')]);

    fireEvent.click(copyButtonOf('1'));
    await screen.findByRole('alert');
    fireEvent.click(copyButtonOf('1'));

    await waitFor(() => {
      expect(alerts()).toEqual(['copy_icon_button.copied']);
    });
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

describe('Archived room', () => {
  it('shows only the copy button, on anyone’s message', async () => {
    await mountRoom(
      [message('1', 'From Bob'), message('2', 'From me', fromMe)],
      true,
    );

    expect(buttonsOf('1')).toEqual(['Copy']);
    expect(buttonsOf('2')).toEqual(['Copy']);
  });

  it('still copies', async () => {
    await mountRoom([message('1', 'From Bob')], true);

    fireEvent.click(copyButtonOf('1'));

    expect(writeText).toHaveBeenCalledWith('From Bob');
    await waitFor(() => {
      expect(alerts()).toEqual(['copy_icon_button.copied']);
    });
  });

  it('has no toolbar when there is nothing to copy', async () => {
    await mountRoom(
      [
        message('1', null, { media_attachments: [picture] }),
        message('2', null, { deleted_at: '2026-11-04T01:00:00Z' }),
      ],
      true,
    );

    expect(toolbarOf('1')).toBeNull();
    expect(toolbarOf('2')).toBeNull();
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

  it('leaves an ordinary mouse press and bubble text alone', async () => {
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
  });

  it('does not suppress mouse focus after a quote touch turns into a scroll', async () => {
    await mountForTouch([
      message('1', 'The original'),
      message('2', 'Reply', { reply_to_id: '1' }),
    ]);
    const quote = bubbleOf('2').querySelector(
      '.chat-native__reply-quote strong',
    );
    if (!quote) throw new Error('Missing quote');
    fireEvent.touchStart(quote, finger(103, 100));
    fireEvent.touchMove(quote, finger(103, 89));
    fireEvent.touchEnd(quote, { touches: [] });
    expect(fireEvent.mouseDown(quote)).toBe(true);
  });

  it('opens the toolbar by focusing the bubble', async () => {
    await mountForTouch([message('1', 'Hello')]);

    fireEvent.touchStart(textOf('1'), finger());
    wait(499);
    expect(document.activeElement).not.toBe(bubbleOf('1'));
    wait(1);

    expect(document.activeElement).toBe(bubbleOf('1'));
    expect(toolbarOf('1')?.closest('article')?.matches(':focus-within')).toBe(
      true,
    );
  });

  it('does not wait for the finger to lift', async () => {
    await mountForTouch([message('1', 'Hello')]);

    fireEvent.touchStart(textOf('1'), finger());
    wait(500);

    expect(document.activeElement).toBe(bubbleOf('1'));
    fireEvent.touchEnd(textOf('1'), { touches: [] });
    expect(document.activeElement).toBe(bubbleOf('1'));
  });

  it('does not scroll the page to the bubble', async () => {
    await mountForTouch([message('1', 'Hello')]);
    const focus = vi.spyOn(bubbleOf('1'), 'focus');

    fireEvent.touchStart(textOf('1'), finger());
    wait(500);

    expect(focus).toHaveBeenCalledWith({ preventScroll: true });
  });

  it('stays closed after a short tap', async () => {
    await mountForTouch([message('1', 'Hello')]);

    fireEvent.touchStart(textOf('1'), finger());
    wait(100);
    fireEvent.touchEnd(textOf('1'), { touches: [] });
    wait(1000);

    expect(document.activeElement).not.toBe(bubbleOf('1'));
  });

  it('stays closed when the finger moves to scroll', async () => {
    await mountForTouch([message('1', 'Hello')]);

    fireEvent.touchStart(textOf('1'), finger(10, 100));
    wait(100);
    fireEvent.touchMove(textOf('1'), finger(10, 89));
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

  it('stays closed when the browser takes the touch over', async () => {
    await mountForTouch([message('1', 'Hello')]);

    fireEvent.touchStart(textOf('1'), finger());
    fireEvent.touchCancel(textOf('1'), { touches: [] });
    wait(1000);

    expect(document.activeElement).not.toBe(bubbleOf('1'));
  });

  it('stays closed when a second finger comes down', async () => {
    await mountForTouch([message('1', 'Hello')]);
    const two = {
      touches: [
        { identifier: 1, clientX: 10, clientY: 10 },
        { identifier: 2, clientX: 50, clientY: 50 },
      ],
    };

    fireEvent.touchStart(textOf('1'), finger());
    fireEvent.touchStart(textOf('1'), two);
    wait(1000);

    expect(document.activeElement).not.toBe(bubbleOf('1'));
  });

  it('leaves a picture in the bubble to the browser', async () => {
    const { container } = await mountForTouch([
      message('1', 'Look', { media_attachments: [picture] }),
    ]);
    const gallery = container.querySelector('.chat-native__gallery');
    if (!gallery) throw new Error('Missing gallery');

    fireEvent.touchStart(gallery, finger());
    wait(1000);

    expect(document.activeElement).not.toBe(bubbleOf('1'));
  });

  it('leaves other attachments in the bubble to the browser', async () => {
    const { container } = await mountForTouch([
      message('1', 'Look', { media_attachments: [pending] }),
    ]);
    const attachment = container.querySelector('.chat-native__attachment');
    if (!attachment) throw new Error('Missing attachment');

    fireEvent.touchStart(attachment, finger());
    wait(1000);

    expect(document.activeElement).not.toBe(bubbleOf('1'));
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
