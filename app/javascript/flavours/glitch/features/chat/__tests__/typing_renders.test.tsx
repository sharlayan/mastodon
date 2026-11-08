import type { ComponentProps } from 'react';

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
const drawn = vi.hoisted(() => ({
  messages: 0,
  room: 0,
  box: 0,
  rows: {},
}));
vi.mock('flavours/glitch/api', () => ({ default: () => api }));
vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<typeof InitialState>()),
  me: 'me',
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
  ColumnHeader: () => {
    drawn.room += 1;
    return <header />;
  },
}));
vi.mock(
  'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container',
  () => ({ default: () => null }),
);
vi.mock('@unhead/react/helmet', () => ({ Helmet: () => null }));
vi.mock('flavours/glitch/components/avatar', () => ({
  Avatar: () => {
    drawn.messages += 1;
    return <div className='account__avatar' />;
  },
}));
vi.mock('react-textarea-autosize', () => ({
  default: ({
    minRows,
    maxRows,
    ...props
  }: ComponentProps<'textarea'> & { minRows?: number; maxRows?: number }) => {
    drawn.box += 1;
    drawn.rows = { minRows, maxRows };
    return <textarea {...props} />;
  },
}));

const me = { id: 'me', acct: 'alice', display_name: 'Alice' };
const other = { id: 'other', acct: 'bob', display_name: 'Bob' };
const ROOM = 'A';
const MESSAGES = `/api/v1/chat/conversations/${ROOM}/messages`;
const PICTURE = {
  id: 'media-1',
  url: '/full-1.png',
  preview_url: '/small-1.png',
  type: 'image',
  description: 'Picture 1',
};

const messageFrom = (index: number, account = index % 2 ? me : other) => ({
  id: `message-${index}`,
  conversation_id: ROOM,
  content: `Message ${index}`,
  created_at: '2026-11-02T00:00:00Z',
  edited_at: null,
  deleted_at: null,
  reply_to_id: null,
  account,
  reactions: [],
  media_attachments: [] as unknown[],
  editable: true,
});
const room = {
  id: ROOM,
  type: 'group',
  title: 'Room A',
  description: null,
  unread: false,
  muted: false,
  archived: false,
  current_role: 'owner',
  accounts: [me, other],
  last_message: null,
};
let shownMessages: ReturnType<typeof messageFrom>[] = [];
const responses = (url: string) => {
  if (url === '/api/v1/chat/conversations')
    return [room, { ...room, id: 'B', title: 'Room B' }];
  if (url === `/api/v1/chat/conversations/${ROOM}`) return room;
  if (url === '/api/v1/chat/conversations/B') return { ...room, id: 'B' };
  if (url === '/api/v1/chat/invitations') return [];
  if (url === '/api/v1/chat/settings')
    return { max_attachments: 4, federation_enabled: true };
  if (url === MESSAGES) return shownMessages;
  if (url.endsWith('/messages')) return [];
  if (url === `/api/v1/chat/conversations/${ROOM}/members`) return [];
  throw new Error(`Unexpected GET ${url}`);
};

const box = () =>
  screen.getByPlaceholderText<HTMLTextAreaElement>('Write a message');
const sendButton = () =>
  screen.getByRole<HTMLButtonElement>('button', { name: 'Send' });
const type = (value: string) => {
  fireEvent.change(box(), { target: { value } });
};
const typeLetters = (word: string, from = '') => {
  let value = from;
  for (const letter of word) {
    value += letter;
    type(value);
  }
};
const rowOf = (text: string) => {
  const row = screen.getByText(text).closest('article');
  if (!row) throw new Error(`No message shows ${text}`);
  return within(row);
};
const posts = (url: string) =>
  api.post.mock.calls.filter(([called]) => called === url);
const lastSent = () => posts(MESSAGES).at(-1)?.[1] as Record<string, unknown>;
const sentMessage = (id: string, text: string) => ({
  ...messageFrom(1, me),
  id,
  content: text,
});
const deferred = <T,>() => {
  let complete!: (value: T) => void;
  let fail!: (reason: unknown) => void;
  const promise = new Promise<T>((resolve, reject) => {
    complete = resolve;
    fail = reject;
  });
  return { promise, resolve: complete, reject: fail };
};
const openRoom = async () => {
  const history = createMemoryHistory({ initialEntries: [`/chat/${ROOM}`] });
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
          <Route path='/chat/:conversationId?/:view?'>
            <Chat />
          </Route>
        </Router>
      </IdentityContext.Provider>
    </IntlProvider>,
  );
  await screen.findByText('Message 5');
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
  return { ...view, history };
};
const drawnWhile = (action: () => void) => {
  const before = { ...drawn };
  action();
  return {
    messages: drawn.messages - before.messages,
    room: drawn.room - before.room,
    box: drawn.box - before.box,
  };
};
const attachPicture = async (container: HTMLElement) => {
  const input = container.querySelector('input[type="file"]');
  if (!input) throw new Error('Missing attachment input');
  fireEvent.change(input, {
    target: { files: [new File(['x'], '1.png', { type: 'image/png' })] },
  });
  await waitFor(() => {
    expect(screen.getByAltText('Picture 1')).toBeTruthy();
  });
};

beforeEach(() => {
  vi.resetAllMocks();
  drawn.messages = 0;
  drawn.room = 0;
  drawn.box = 0;
  shownMessages = Array.from({ length: 6 }, (_, index) => messageFrom(index));
  api.get.mockImplementation((url: string) =>
    Promise.resolve({ data: responses(url) }),
  );
  api.post.mockImplementation((url: string, body: { text?: string }) =>
    Promise.resolve({
      data:
        url === '/api/v2/media'
          ? PICTURE
          : url === MESSAGES
            ? sentMessage('sent', body.text ?? '')
            : {},
    }),
  );
  api.patch.mockImplementation((_url: string, body: { text?: string }) =>
    Promise.resolve({ data: sentMessage('message-5', body.text ?? '') }),
  );
  Element.prototype.scrollIntoView = vi.fn();
});

afterEach(() => {
  cleanup();
  Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
  vi.restoreAllMocks();
});

describe('Typing in a room', () => {
  it('draws the messages at all, or the counts below would prove nothing', async () => {
    await openRoom();

    expect(drawn.messages).toBeGreaterThan(0);
    expect(drawn.room).toBeGreaterThan(0);
  });

  it('draws neither the messages nor the room for the letters typed', async () => {
    await openRoom();

    const typing = drawnWhile(() => {
      typeLetters('seventeen letters');
    });

    expect(typing).toEqual({ messages: 0, room: 0, box: 17 });
    expect(box().value).toBe('seventeen letters');
  });

  it('draws neither the messages nor the room when the Send button changes', async () => {
    await openRoom();
    expect(sendButton().disabled).toBe(true);

    const enabling = drawnWhile(() => {
      type('a');
    });
    expect(sendButton().disabled).toBe(false);
    const disabling = drawnWhile(() => {
      type('');
    });
    expect(sendButton().disabled).toBe(true);

    expect(enabling).toEqual({ messages: 0, room: 0, box: 1 });
    expect(disabling).toEqual({ messages: 0, room: 0, box: 1 });
  });

  it('draws neither the messages nor the room when a message gets too long', async () => {
    await openRoom();

    const typing = drawnWhile(() => {
      type('x'.repeat(4097));
    });

    expect(typing).toEqual({ messages: 0, room: 0, box: 1 });
    expect(screen.getByText(/This message is too long/)).toBeTruthy();
  });

  it('does not bring back drawing the messages when scrolling with something typed', async () => {
    await openRoom();
    type('Typed');

    const scrolling = drawnWhile(() => {
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
        bottom: window.innerHeight + 5000,
      } as DOMRect);
      fireEvent.scroll(window);
    });

    expect(scrolling).toEqual({ messages: 0, room: 0, box: 0 });
    expect(box().value).toBe('Typed');
  });

  it('keeps the size limits of the box', async () => {
    await openRoom();

    type('Typed');

    expect(drawn.rows).toEqual({ minRows: 1, maxRows: 6 });
  });

  it('only offers Send when there is something to send', async () => {
    await openRoom();

    type('   ');
    expect(sendButton().disabled).toBe(true);

    type('  a ');
    expect(sendButton().disabled).toBe(false);
  });

  it('does not send a message that is too long, and offers it again once it fits', async () => {
    await openRoom();

    type('x'.repeat(4097));
    expect(screen.getByText(/4097\/4096/)).toBeTruthy();
    expect(sendButton().disabled).toBe(true);
    fireEvent.keyDown(box(), { key: 'Enter' });
    expect(posts(MESSAGES)).toHaveLength(0);

    type('x'.repeat(4096));
    expect(screen.queryByText(/This message is too long/)).toBeNull();
    expect(sendButton().disabled).toBe(false);
  });
});

describe('Sending what was typed', () => {
  it('sends what the box holds with Enter, after letters that drew nothing else', async () => {
    await openRoom();

    typeLetters('Typed one by one');
    fireEvent.keyDown(box(), { key: 'Enter' });

    await waitFor(() => {
      expect(lastSent()).toMatchObject({ text: 'Typed one by one' });
    });
    await waitFor(() => {
      expect(box().value).toBe('');
    });
    expect(screen.getByText('Typed one by one')).toBeTruthy();
  });

  it('sends what the box holds with the button, and trims it', async () => {
    await openRoom();

    typeLetters('  Typed ');
    fireEvent.click(sendButton());

    await waitFor(() => {
      expect(lastSent()).toMatchObject({ text: 'Typed' });
    });
  });

  it('keeps the focus in the box when the button is pressed, before and after sending', async () => {
    await openRoom();
    box().focus();
    typeLetters('Typed');

    const notPrevented = fireEvent.mouseDown(sendButton());
    expect(notPrevented).toBe(false);
    fireEvent.click(sendButton());

    await waitFor(() => {
      expect(box().value).toBe('');
    });
    expect(document.activeElement).toBe(box());
    expect(box().readOnly).toBe(false);
    expect(box().disabled).toBe(false);
  });

  it('keeps what is typed while sending, and only what went out leaves the box', async () => {
    const sending = deferred<{ data: unknown }>();
    await openRoom();
    api.post.mockImplementation((url: string) =>
      url === MESSAGES ? sending.promise : Promise.resolve({ data: {} }),
    );

    type('First');
    fireEvent.keyDown(box(), { key: 'Enter' });
    await waitFor(() => {
      expect(posts(MESSAGES)).toHaveLength(1);
    });
    typeLetters(' and more', 'First');

    await act(async () => {
      sending.resolve({ data: sentMessage('sent', 'First') });
      await sending.promise;
    });

    await waitFor(() => {
      expect(box().value).toBe(' and more');
    });
    expect(lastSent()).toMatchObject({ text: 'First' });
  });

  it('leaves the box alone when it was changed altogether while sending', async () => {
    const sending = deferred<{ data: unknown }>();
    await openRoom();
    api.post.mockImplementation((url: string) =>
      url === MESSAGES ? sending.promise : Promise.resolve({ data: {} }),
    );

    type('First');
    fireEvent.keyDown(box(), { key: 'Enter' });
    await waitFor(() => {
      expect(posts(MESSAGES)).toHaveLength(1);
    });
    type('Something else');

    await act(async () => {
      sending.resolve({ data: sentMessage('sent', 'First') });
      await sending.promise;
    });

    await screen.findByText('First');
    expect(box().value).toBe('Something else');
  });

  it('does not send twice while sending', async () => {
    const sending = deferred<{ data: unknown }>();
    await openRoom();
    api.post.mockImplementation((url: string) =>
      url === MESSAGES ? sending.promise : Promise.resolve({ data: {} }),
    );

    type('First');
    fireEvent.keyDown(box(), { key: 'Enter' });
    await waitFor(() => {
      expect(posts(MESSAGES)).toHaveLength(1);
    });
    fireEvent.keyDown(box(), { key: 'Enter' });
    fireEvent.click(sendButton());

    expect(posts(MESSAGES)).toHaveLength(1);
    await act(async () => {
      sending.resolve({ data: sentMessage('sent', 'First') });
      await sending.promise;
    });
  });

  it('keeps the text when sending fails', async () => {
    await openRoom();
    api.post.mockImplementation((url: string) =>
      url === MESSAGES
        ? Promise.reject(new Error('no'))
        : Promise.resolve({ data: {} }),
    );

    type('Typed');
    fireEvent.keyDown(box(), { key: 'Enter' });

    await waitFor(() => {
      expect(posts(MESSAGES)).toHaveLength(1);
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(box().value).toBe('Typed');
    expect(sendButton().disabled).toBe(false);
  });
});

describe('Korean input', () => {
  const composing = (value: string) => {
    fireEvent.compositionUpdate(box(), { data: value });
    type(value);
  };

  it('shows each step of a syllable, drawing only the box', async () => {
    await openRoom();
    fireEvent.compositionStart(box());

    const typing = drawnWhile(() => {
      for (const step of ['ㅎ', '하', '한', '한ㄱ', '한그', '한글']) {
        composing(step);
        expect(box().value).toBe(step);
      }
    });
    fireEvent.compositionEnd(box(), { data: '글' });

    expect(typing).toEqual({ messages: 0, room: 0, box: 6 });
    expect(box().value).toBe('한글');
  });

  it('does not send when Enter confirms a syllable', async () => {
    await openRoom();
    fireEvent.compositionStart(box());
    composing('한');

    fireEvent.keyDown(box(), { key: 'Enter', isComposing: true });
    fireEvent.keyDown(box(), { key: 'Enter', keyCode: 229 });

    expect(posts(MESSAGES)).toHaveLength(0);
    expect(box().value).toBe('한');
  });

  it('sends the whole word once the syllable is confirmed', async () => {
    await openRoom();
    fireEvent.compositionStart(box());
    composing('한글');
    fireEvent.compositionEnd(box(), { data: '글' });

    fireEvent.keyDown(box(), { key: 'Enter' });

    await waitFor(() => {
      expect(lastSent()).toMatchObject({ text: '한글' });
    });
    await waitFor(() => {
      expect(box().value).toBe('');
    });
  });

  it('sends the syllable being composed with the button, and empties the box', async () => {
    await openRoom();
    box().focus();
    fireEvent.compositionStart(box());
    composing('안녕');

    fireEvent.mouseDown(sendButton());
    fireEvent.click(sendButton());

    await waitFor(() => {
      expect(lastSent()).toMatchObject({ text: '안녕' });
    });
    await waitFor(() => {
      expect(box().value).toBe('');
    });
    expect(document.activeElement).toBe(box());
  });
});

describe('Typing while replying', () => {
  it('sends the reply with what was typed before and after choosing the message', async () => {
    await openRoom();
    typeLetters('Before ');

    fireEvent.click(rowOf('Message 4').getByRole('button', { name: 'Reply' }));
    expect(screen.getByText('Replying to Bob')).toBeTruthy();
    typeLetters('after', 'Before ');
    fireEvent.keyDown(box(), { key: 'Enter' });

    await waitFor(() => {
      expect(lastSent()).toMatchObject({
        text: 'Before after',
        reply_to_id: 'message-4',
      });
    });
    await waitFor(() => {
      expect(screen.queryByText('Replying to Bob')).toBeNull();
    });
    expect(box().value).toBe('');
  });

  it('replies to a message that arrived while typing', async () => {
    await openRoom();
    typeLetters('Typed');

    act(() => {
      emitChatStreamEvent({
        event: 'chat.message',
        payload: {
          ...messageFrom(0, other),
          id: 'live',
          content: 'Arrived while typing',
        },
      });
    });
    expect(box().value).toBe('Typed');
    fireEvent.click(
      rowOf('Arrived while typing').getByRole('button', { name: 'Reply' }),
    );
    fireEvent.keyDown(box(), { key: 'Enter' });

    await waitFor(() => {
      expect(lastSent()).toMatchObject({ text: 'Typed', reply_to_id: 'live' });
    });
  });
});

describe('Typing while editing', () => {
  const edit = () => {
    fireEvent.click(rowOf('Message 5').getByRole('button', { name: 'Edit' }));
  };

  it('puts the draft aside, and brings back what was typed last after saving', async () => {
    await openRoom();
    typeLetters('My draft');

    edit();
    expect(box().value).toBe('Message 5');
    typeLetters(' edited', 'Message 5');
    fireEvent.keyDown(box(), { key: 'Enter' });

    await waitFor(() => {
      expect(api.patch).toHaveBeenCalledWith(
        '/api/v1/chat/messages/message-5',
        { text: 'Message 5 edited' },
      );
    });
    await waitFor(() => {
      expect(box().value).toBe('My draft');
    });
    expect(screen.queryByText('Editing message')).toBeNull();
  });

  it('brings back what was typed last when cancelling', async () => {
    await openRoom();
    typeLetters('My draft');

    edit();
    typeLetters(' dropped', 'Message 5');
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(box().value).toBe('My draft');
    expect(screen.queryByText('Editing message')).toBeNull();
  });

  it('keeps the first draft when another message is edited on the way', async () => {
    shownMessages = [...shownMessages, messageFrom(7, me)];
    await openRoom();
    typeLetters('My draft');

    edit();
    fireEvent.click(rowOf('Message 7').getByRole('button', { name: 'Edit' }));
    expect(box().value).toBe('Message 7');
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(box().value).toBe('My draft');
  });

  it('brings back the draft without complaint when the message is deleted elsewhere', async () => {
    const complaints = vi.spyOn(console, 'error');
    await openRoom();
    typeLetters('My draft');
    edit();

    act(() => {
      emitChatStreamEvent({
        event: 'chat.message_delete',
        payload: { id: 'message-5', conversation_id: ROOM },
      });
    });

    await waitFor(() => {
      expect(screen.queryByText('Editing message')).toBeNull();
    });
    expect(box().value).toBe('My draft');
    expect(complaints).not.toHaveBeenCalled();
  });

  it('brings back the draft without complaint when the room is archived', async () => {
    const complaints = vi.spyOn(console, 'error');
    await openRoom();
    typeLetters('My draft');
    edit();

    act(() => {
      emitChatStreamEvent({
        event: 'chat.conversation_update',
        payload: { ...room, archived: true },
      });
    });

    await waitFor(() => {
      expect(screen.queryByText('Editing message')).toBeNull();
    });
    expect(box().value).toBe('My draft');
    expect(box().disabled).toBe(true);
    expect(complaints).not.toHaveBeenCalled();
  });

  it('can save a message with pictures with nothing typed', async () => {
    shownMessages = [
      ...shownMessages,
      { ...messageFrom(7, me), media_attachments: [PICTURE] },
    ];
    await openRoom();

    fireEvent.click(rowOf('Message 7').getByRole('button', { name: 'Edit' }));
    type('');

    expect(
      screen.getByRole<HTMLButtonElement>('button', { name: 'Save' }).disabled,
    ).toBe(false);
  });
});

describe('Typing with a picture attached', () => {
  it('sends the picture with what is typed after attaching it, and empties both', async () => {
    const { container } = await openRoom();

    await attachPicture(container);
    typeLetters('With a picture');
    fireEvent.keyDown(box(), { key: 'Enter' });

    await waitFor(() => {
      expect(lastSent()).toMatchObject({
        text: 'With a picture',
        media_ids: ['media-1'],
      });
    });
    await waitFor(() => {
      expect(screen.queryByAltText('Picture 1')).toBeNull();
    });
    expect(box().value).toBe('');
  });

  it('can send a picture with nothing typed', async () => {
    const { container } = await openRoom();
    expect(sendButton().disabled).toBe(true);

    await attachPicture(container);
    expect(sendButton().disabled).toBe(false);
    fireEvent.click(sendButton());

    await waitFor(() => {
      expect(lastSent()).toMatchObject({ text: '', media_ids: ['media-1'] });
    });
  });

  it('keeps the picture when what was typed is rubbed out', async () => {
    const { container } = await openRoom();
    await attachPicture(container);

    typeLetters('Typed');
    type('');

    expect(screen.getByAltText('Picture 1')).toBeTruthy();
    expect(sendButton().disabled).toBe(false);
  });
});

describe('What was typed, on the way around the room', () => {
  it('is still there after visiting the members of the room', async () => {
    const { history } = await openRoom();
    typeLetters('My draft');

    act(() => {
      history.push(`/chat/${ROOM}/members`);
    });
    await waitFor(() => {
      expect(screen.queryByPlaceholderText('Write a message')).toBeNull();
    });
    act(() => {
      history.push(`/chat/${ROOM}`);
    });

    await waitFor(() => {
      expect(box().value).toBe('My draft');
    });
    expect(sendButton().disabled).toBe(false);
  });

  it('does not follow to another room', async () => {
    const { history } = await openRoom();
    typeLetters('My draft');

    act(() => {
      history.push('/chat/B');
    });

    await waitFor(() => {
      expect(box().value).toBe('');
    });
    expect(sendButton().disabled).toBe(true);
  });
});
