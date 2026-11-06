import type { ComponentProps } from 'react';

import { IntlProvider } from 'react-intl';

import { Route, Router } from 'react-router-dom';

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
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
// What the room draws for a message and for the box to write in, counted each time they are drawn.
const drawn = vi.hoisted(() => ({ messages: 0, composer: 0 }));
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
  ColumnHeader: () => <header />,
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
    minRows: _minRows,
    maxRows: _maxRows,
    ...props
  }: ComponentProps<'textarea'> & { minRows?: number; maxRows?: number }) => {
    drawn.composer += 1;
    return <textarea {...props} />;
  },
}));

const me = { id: 'me', acct: 'alice', display_name: 'Alice' };
const other = { id: 'other', acct: 'bob', display_name: 'Bob' };
const ROOM = 'A';
const JUMP = 'Jump to newest message';
const READ = `/api/v1/chat/conversations/${ROOM}/read`;

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
  media_attachments: [],
});
const room = {
  id: ROOM,
  type: 'direct',
  title: null,
  description: null,
  unread: false,
  muted: false,
  archived: false,
  current_role: 'member',
  accounts: [me, other],
  last_message: null,
};
const responses = (url: string) => {
  if (url === '/api/v1/chat/conversations') return [room];
  if (url === `/api/v1/chat/conversations/${ROOM}`) return room;
  if (url === '/api/v1/chat/invitations') return [];
  if (url === '/api/v1/chat/settings')
    return { max_attachments: 4, federation_enabled: true };
  if (url.endsWith('/messages'))
    return Array.from({ length: 6 }, (_, index) => messageFrom(index));
  throw new Error(`Unexpected GET ${url}`);
};

const scrollIntoView = vi.fn();
const placedAt = (bottom: number) => {
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
    bottom: window.innerHeight + bottom,
  } as DOMRect);
  fireEvent.scroll(window);
};
const scrollUp = () => {
  placedAt(5000);
};
const scrollToBottom = () => {
  placedAt(0);
};
const openRoom = async () => {
  const history = createMemoryHistory({ initialEntries: [`/chat/${ROOM}`] });
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
};
const receive = (id: string, account = other) => {
  act(() => {
    emitChatStreamEvent({
      event: 'chat.message',
      payload: { ...messageFrom(0, account), id, content: `Live ${id}` },
    });
  });
};
const readsPosted = () =>
  api.post.mock.calls.filter(([url]) => url === READ).length;
// Runs what the reader does, and gives back how many times the room drew its messages and its box meanwhile.
const drawnWhile = (action: () => void) => {
  const before = { ...drawn };
  action();
  return {
    messages: drawn.messages - before.messages,
    composer: drawn.composer - before.composer,
  };
};
const NOTHING = { messages: 0, composer: 0 };
const originalMatchMedia = Object.getOwnPropertyDescriptor(
  window,
  'matchMedia',
);

beforeEach(() => {
  vi.resetAllMocks();
  Object.defineProperty(window, 'matchMedia', {
    configurable: true,
    writable: true,
    value: vi.fn().mockReturnValue({ matches: false }),
  });
  drawn.messages = 0;
  drawn.composer = 0;
  api.get.mockImplementation((url: string) =>
    Promise.resolve({ data: responses(url) }),
  );
  api.post.mockResolvedValue({ data: {} });
  scrollIntoView.mockClear();
  Element.prototype.scrollIntoView = scrollIntoView;
});

afterEach(() => {
  cleanup();
  Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
  vi.restoreAllMocks();
  if (originalMatchMedia)
    Object.defineProperty(window, 'matchMedia', originalMatchMedia);
  else Reflect.deleteProperty(window, 'matchMedia');
});

describe('Scrolling in a room', () => {
  it('finishes opening at the actual bottom of the chat scrollport', async () => {
    scrollIntoView.mockImplementation(function (this: HTMLElement) {
      const scrollport = this.closest('.chat-native') as HTMLElement;
      scrollport.style.overflowY = 'auto';
      Object.defineProperty(scrollport, 'clientHeight', {
        configurable: true,
        value: 400,
      });
      Object.defineProperty(scrollport, 'scrollHeight', {
        configurable: true,
        value: 1000,
      });
      scrollport.scrollTop = 530;
    });
    await openRoom();
    expect(
      (document.querySelector('.chat-native') as HTMLElement).scrollTop,
    ).toBe(1000);
  });

  it('realigns when the visible viewport resizes only while following the newest message', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    try {
      await openRoom();
      scrollIntoView.mockClear();
      viewport.height = 500;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(scrollIntoView).toHaveBeenCalled();
      scrollUp();
      scrollIntoView.mockClear();
      viewport.height = 450;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(scrollIntoView).not.toHaveBeenCalled();
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('does not snap to the composer when pinch zoom changes the viewport scale', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    try {
      await openRoom();
      scrollIntoView.mockClear();
      viewport.scale = 2;
      viewport.height = 333;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(scrollIntoView).not.toHaveBeenCalled();
      viewport.scale = 1;
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(scrollIntoView).not.toHaveBeenCalled();
      viewport.height = 500;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(scrollIntoView).toHaveBeenCalled();
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('does not scroll to the document end when the touch keyboard resizes the viewport', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const originalMatch = Object.getOwnPropertyDescriptor(window, 'matchMedia');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      scrollIntoView.mockClear();
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(scrollIntoView).not.toHaveBeenCalled();
    } finally {
      if (originalMatch)
        Object.defineProperty(window, 'matchMedia', originalMatch);
      else Reflect.deleteProperty(window, 'matchMedia');
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('preserves the reading position when keyboard-driven scrolling resembles reaching the bottom', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const originalMatch = Object.getOwnPropertyDescriptor(window, 'matchMedia');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      const scrollport = document.querySelector('.chat-native') as HTMLElement;
      scrollport.style.overflowY = 'auto';
      Object.defineProperty(scrollport, 'clientHeight', {
        configurable: true,
        value: 200,
      });
      Object.defineProperty(scrollport, 'scrollHeight', {
        configurable: true,
        value: 1000,
      });
      scrollport.scrollTop = 250;
      scrollUp();
      expect(screen.queryByRole('button', { name: JUMP })).not.toBeNull();
      const box = screen.getByRole('textbox');
      act(() => {
        box.focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      scrollport.scrollTop = 500;
      placedAt(0);
      scrollIntoView.mockClear();
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(scrollIntoView).not.toHaveBeenCalled();
      expect(screen.queryByRole('button', { name: JUMP })).not.toBeNull();
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 250));
      });
      expect(scrollport.scrollTop).toBe(250);
    } finally {
      if (originalMatch)
        Object.defineProperty(window, 'matchMedia', originalMatch);
      else Reflect.deleteProperty(window, 'matchMedia');
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('reveals the last message with only the required scroll when the keyboard opens', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const originalMatch = Object.getOwnPropertyDescriptor(window, 'matchMedia');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      const scrollport = document.querySelector('.chat-native') as HTMLElement;
      scrollport.style.overflowY = 'auto';
      Object.defineProperty(scrollport, 'clientHeight', {
        configurable: true,
        value: 200,
      });
      Object.defineProperty(scrollport, 'scrollHeight', {
        configurable: true,
        value: 1000,
      });
      scrollport.scrollTop = 800;
      act(() => {
        screen.getByRole('textbox').focus();
      });
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          return {
            top: this.classList.contains('chat-native__composer') ? 180 : 0,
            bottom: 250,
          } as DOMRect;
        },
      );
      Object.defineProperty(scrollport, 'scrollHeight', {
        configurable: true,
        value: 1200,
      });
      viewport.height = 307;
      scrollIntoView.mockClear();
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(scrollIntoView).not.toHaveBeenCalled();
      expect(scrollport.scrollTop).toBe(886);
    } finally {
      if (originalMatch)
        Object.defineProperty(window, 'matchMedia', originalMatch);
      else Reflect.deleteProperty(window, 'matchMedia');
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('honours an explicit scroll while the touch keyboard is open', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const originalMatch = Object.getOwnPropertyDescriptor(window, 'matchMedia');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      scrollUp();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      fireEvent.wheel(window);
      placedAt(307 - window.innerHeight);
      expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 250));
      });
      expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
    } finally {
      if (originalMatch)
        Object.defineProperty(window, 'matchMedia', originalMatch);
      else Reflect.deleteProperty(window, 'matchMedia');
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('preserves a slightly older position even within the follow threshold', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const originalMatch = Object.getOwnPropertyDescriptor(window, 'matchMedia');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      const scrollport = document.querySelector('.chat-native') as HTMLElement;
      scrollport.style.overflowY = 'auto';
      Object.defineProperty(scrollport, 'clientHeight', {
        configurable: true,
        value: 200,
      });
      Object.defineProperty(scrollport, 'scrollHeight', {
        configurable: true,
        value: 1000,
      });
      scrollport.scrollTop = 700;
      placedAt(100);
      expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      scrollport.scrollTop = 800;
      placedAt(0);
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 250));
      });
      expect(scrollport.scrollTop).toBe(700);
      expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
    } finally {
      if (originalMatch)
        Object.defineProperty(window, 'matchMedia', originalMatch);
      else Reflect.deleteProperty(window, 'matchMedia');
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('reveals a new message without scrolling past the composer during keyboard focus', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const originalMatch = Object.getOwnPropertyDescriptor(window, 'matchMedia');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      const scrollport = document.querySelector('.chat-native') as HTMLElement;
      scrollport.style.overflowY = 'auto';
      Object.defineProperty(scrollport, 'clientHeight', {
        configurable: true,
        value: 200,
      });
      Object.defineProperty(scrollport, 'scrollHeight', {
        configurable: true,
        value: 1000,
      });
      scrollport.scrollTop = 600;
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          return {
            top: this.classList.contains('chat-native__composer') ? 180 : 0,
            bottom: 200,
          } as DOMRect;
        },
      );
      scrollIntoView.mockClear();
      receive('new-while-keyboard');
      expect(scrollIntoView).not.toHaveBeenCalled();
      expect(scrollport.scrollTop).toBe(636);
    } finally {
      if (originalMatch)
        Object.defineProperty(window, 'matchMedia', originalMatch);
      else Reflect.deleteProperty(window, 'matchMedia');
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('keeps a deliberate send at the newest message after the keyboard closes', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const originalMatch = Object.getOwnPropertyDescriptor(window, 'matchMedia');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      scrollUp();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      receive('sent-while-keyboard', me);
      expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 250));
      });
      expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
    } finally {
      if (originalMatch)
        Object.defineProperty(window, 'matchMedia', originalMatch);
      else Reflect.deleteProperty(window, 'matchMedia');
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('does not move the scrollport when a message arrives while reading older ones', async () => {
    await openRoom();
    const scrollport = document.querySelector('.chat-native') as HTMLElement;
    scrollport.style.overflowY = 'auto';
    Object.defineProperty(scrollport, 'clientHeight', {
      configurable: true,
      value: 400,
    });
    Object.defineProperty(scrollport, 'scrollHeight', {
      configurable: true,
      value: 1000,
    });
    scrollport.scrollTop = 100;
    scrollUp();
    receive('older-reading');
    expect(scrollport.scrollTop).toBe(100);
  });

  it('draws the messages at all, or the counts below would prove nothing', async () => {
    await openRoom();

    expect(drawn.messages).toBeGreaterThan(0);
    expect(drawn.composer).toBeGreaterThan(0);
  });

  it('shows the way back without drawing the messages or the box again', async () => {
    await openRoom();

    expect(drawnWhile(scrollUp)).toEqual(NOTHING);

    expect(screen.getByRole('button', { name: JUMP })).toBeTruthy();
  });

  it('hides the way back without drawing the messages or the box again', async () => {
    await openRoom();
    scrollUp();

    expect(drawnWhile(scrollToBottom)).toEqual(NOTHING);

    expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
  });

  it('draws nothing again over several trips, or while staying on one side', async () => {
    await openRoom();

    const trips = drawnWhile(() => {
      for (let trip = 0; trip < 4; trip++) {
        scrollUp();
        scrollUp();
        scrollToBottom();
        scrollToBottom();
      }
    });

    expect(trips).toEqual(NOTHING);
  });

  it('tells about a message that arrives while reading older ones, and draws it', async () => {
    await openRoom();
    scrollUp();

    const arriving = drawnWhile(() => {
      receive('live');
    });

    expect(screen.getByText('New messages')).toBeTruthy();
    expect(screen.getByText('Live live')).toBeTruthy();
    expect(arriving.messages).toBeGreaterThan(0);
  });

  it('does not count a message as read while reading older ones', async () => {
    await openRoom();
    scrollUp();
    const before = readsPosted();

    receive('live');
    scrollUp();

    expect(readsPosted()).toBe(before);
  });

  // Only the notice going away is counted here. The server's answer to reading the room updates the list of rooms,
  // and that does draw the room again: it happens when a message went unseen, not each time the button comes and goes.
  it('clears the notice and asks to read the room on returning to the bottom, and clearing it draws nothing again', async () => {
    await openRoom();
    scrollUp();
    receive('live');
    const before = readsPosted();

    expect(drawnWhile(scrollToBottom)).toEqual(NOTHING);

    expect(screen.queryByText('New messages')).toBeNull();
    expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
    expect(readsPosted()).toBe(before + 1);
  });

  it('clears the notice, asks to read the room and goes down with the button, and clearing it draws nothing again', async () => {
    await openRoom();
    scrollUp();
    receive('live');
    const before = readsPosted();
    scrollIntoView.mockClear();

    expect(
      drawnWhile(() => {
        fireEvent.click(screen.getByRole('button', { name: 'New messages' }));
      }),
    ).toEqual(NOTHING);

    expect(screen.queryByText('New messages')).toBeNull();
    expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
    expect(readsPosted()).toBe(before + 1);
    expect(scrollIntoView).toHaveBeenCalledTimes(1);
  });

  it('keeps the notice while still reading older ones', async () => {
    await openRoom();
    scrollUp();
    receive('live');

    scrollUp();

    expect(screen.getByText('New messages')).toBeTruthy();
  });

  it('goes down for a message of mine while reading older ones', async () => {
    await openRoom();
    scrollUp();
    scrollIntoView.mockClear();

    receive('mine', me);

    expect(scrollIntoView).toHaveBeenCalled();
    expect(screen.queryByText('New messages')).toBeNull();
  });

  it('starts a room with no way back, when moving on from one that had it', async () => {
    await openRoom();
    scrollUp();
    receive('live');
    cleanup();

    await openRoom();

    expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
    expect(screen.queryByText('New messages')).toBeNull();
  });
});
