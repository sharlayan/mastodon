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
// The end of the room `bottom` px below the window. When a test lets the room scroll in a box of its own, that box
// covers the window, as a column does: what can be seen of the room is within it.
const placedAt = (bottom: number) => {
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
    function (this: Element) {
      if (this.classList.contains('chat-native__end'))
        return {
          top: window.innerHeight + bottom,
          bottom: window.innerHeight + bottom,
        } as DOMRect;
      if (this.classList.contains('chat-native__composer'))
        return { top: 300, bottom: 350 } as DOMRect;
      if (this.classList.contains('chat-native'))
        return { top: 0, bottom: window.innerHeight } as DOMRect;
      return { top: 100, bottom: 150 } as DOMRect;
    },
  );
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
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
    function (this: Element) {
      if (this.classList.contains('chat-native__composer'))
        return { top: 300, bottom: 350 } as DOMRect;
      return { top: 100, bottom: 150 } as DOMRect;
    },
  );
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
  it('does not mark a message read when the composer still obscures it', async () => {
    await openRoom();
    const before = readsPosted();
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function (this: Element) {
        if (this.classList.contains('chat-native__composer'))
          return { top: 180, bottom: 230 } as DOMRect;
        if (this.id === 'chat-message-obscured')
          return { top: 200, bottom: 220 } as DOMRect;
        return { top: 0, bottom: 100 } as DOMRect;
      },
    );
    receive('obscured');
    expect(readsPosted()).toBe(before);
    placedAt(0);
    expect(readsPosted()).toBe(before + 1);
  });

  it('does not follow or mark a new message during zoom even without a scroll event', async () => {
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
      viewport.scale = 2;
      const before = readsPosted();
      scrollIntoView.mockClear();
      receive('zoomed-without-scroll');
      expect(scrollIntoView).not.toHaveBeenCalled();
      expect(readsPosted()).toBe(before);
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('does not scroll or mark incoming messages read while zoomed', async () => {
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
      viewport.scale = 2;
      scrollUp();
      const before = readsPosted();
      scrollIntoView.mockClear();
      receive('zoomed');
      expect(scrollIntoView).not.toHaveBeenCalled();
      expect(readsPosted()).toBe(before);
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('does not restore an old following position after zooming and panning with the keyboard open', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
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
      viewport.scale = 2;
      scrollUp();
      viewport.scale = 1;
      scrollIntoView.mockClear();
      act(() => {
        screen.getByRole('textbox').blur();
      });
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 750));
      });
      expect(scrollIntoView).not.toHaveBeenCalled();
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('keeps the newest message after closing a focused composer near the bottom', async () => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
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
    act(() => {
      screen.getByRole('textbox').focus();
    });
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function (this: Element) {
        return {
          top: this.classList.contains('chat-native__composer') ? 180 : 0,
          bottom: 200,
        } as DOMRect;
      },
    );
    receive('keyboard-follow');
    const afterMessage = scrollport.scrollTop;
    expect(afterMessage).toBeGreaterThan(700);
    act(() => {
      screen.getByRole('textbox').blur();
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 750));
    });
    expect(scrollport.scrollTop).toBeGreaterThanOrEqual(afterMessage);
  });

  it('preserves the end of inertial scrolling while the keyboard is open', async () => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
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
    scrollport.scrollTop = 500;
    scrollUp();
    act(() => {
      screen.getByRole('textbox').focus();
    });
    fireEvent.touchMove(window);
    scrollport.scrollTop = 300;
    placedAt(5000);
    for (let i = 0; i < 6; i++) {
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 100));
      });
      scrollport.scrollTop = 300 - i * 5;
      placedAt(5000);
    }
    scrollport.scrollTop = 250;
    placedAt(5000);
    act(() => {
      screen.getByRole('textbox').blur();
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 750));
    });
    expect(scrollport.scrollTop).toBe(250);
  });

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
      expect(scrollport.scrollTop).toBeGreaterThanOrEqual(700);
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

  it('keeps the reading position after a send while the keyboard closes', async () => {
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
      expect(screen.queryByRole('button', { name: JUMP })).not.toBeNull();
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 250));
      });
      expect(screen.queryByRole('button', { name: JUMP })).not.toBeNull();
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

  it('does not go down for a message of mine while reading older ones', async () => {
    await openRoom();
    scrollUp();
    scrollIntoView.mockClear();

    receive('mine', me);

    expect(scrollIntoView).not.toHaveBeenCalled();
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

// ---- Review 355b: reproductions appended to a copy of scroll_renders.test.tsx ----
const withQuote = () => {
  api.get.mockImplementation((url: string) => {
    if (url.endsWith('/messages'))
      return Promise.resolve({
        data: Array.from({ length: 6 }, (_, index) => ({
          ...messageFrom(index),
          reply_to_id: index === 5 ? 'message-1' : null,
        })),
      });
    return Promise.resolve({ data: responses(url) });
  });
};
const tallScrollport = (top: number) => {
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
  scrollport.scrollTop = top;
  return scrollport;
};
const endScrolls = () =>
  scrollIntoView.mock.contexts.filter((element) =>
    (element as Element).classList.contains('chat-native__end'),
  ).length;

describe('Review 355b', () => {
  it('does not snap back while a quoted message is still loading', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    let release!: (value: { data: ReturnType<typeof messageFrom>[] }) => void;
    const older = new Promise<{ data: ReturnType<typeof messageFrom>[] }>(
      (resolve) => {
        release = resolve;
      },
    );
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages')) {
          if (options?.params?.max_id) return older;
          return Promise.resolve({
            data: Array.from({ length: 40 }, (_, i) => ({
              ...messageFrom(i + 20),
              reply_to_id: i === 39 ? 'message-1' : null,
            })),
          });
        }
        return Promise.resolve({ data: responses(url) });
      },
    );
    try {
      const history = createMemoryHistory({
        initialEntries: [`/chat/${ROOM}`],
      });
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
      await screen.findByText('Message 59');
      const scrollport = tallScrollport(800);
      placedAt(0);
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      const quote = document.querySelector(
        '.chat-native__reply-quote[data-message-id="message-1"]',
      ) as HTMLElement;
      scrollIntoView.mockClear();
      fireEvent.pointerDown(quote);
      act(() => {
        screen.getByRole('textbox').blur();
      });
      fireEvent.click(quote);
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 300));
      });
      expect(scrollport.scrollTop).toBe(800);
      expect(endScrolls()).toBe(0);
      await act(async () => {
        release({ data: Array.from({ length: 20 }, (_, i) => messageFrom(i)) });
        await older;
      });
      expect(document.getElementById('chat-message-message-1')).not.toBeNull();
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });
  it('keeps a quote jump when keyboard closure resizes the viewport', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
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
      withQuote();
      await openRoom();
      const scrollport = tallScrollport(800);
      placedAt(0);
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      const quote = document.querySelector(
        '.chat-native__reply-quote[data-message-id="message-1"]',
      ) as HTMLElement;
      scrollIntoView.mockClear();
      scrollIntoView.mockImplementation(function (this: HTMLElement) {
        if (this.id === 'chat-message-message-1') scrollport.scrollTop = 100;
      });
      fireEvent.pointerDown(quote);
      act(() => {
        screen.getByRole('textbox').blur();
      });
      fireEvent.click(quote);
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 300));
      });
      expect(scrollport.scrollTop).toBe(100);
      expect(endScrolls()).toBe(0);
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('does not read the newest message while loading an older searched target', async () => {
    // Opened at an older message: the end of the room, and the newest message above it, are below the screen.
    placedAt(5000);
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages')) {
          const start = options?.params?.max_id ? 0 : 20;
          const length = start === 0 ? 20 : 40;
          return Promise.resolve({
            data: Array.from({ length }, (_, i) => messageFrom(start + i)),
          });
        }
        return Promise.resolve({ data: responses(url) });
      },
    );
    const history = createMemoryHistory({
      initialEntries: [
        { pathname: `/chat/${ROOM}`, state: { chatMessageId: 'message-1' } },
      ],
    });
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
    await screen.findByText('Message 1');
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 50));
    });
    expect(readsPosted()).toBe(0);
    expect(
      scrollIntoView.mock.contexts.some((element) =>
        (element as Element).classList.contains('chat-native__end'),
      ),
    ).toBe(false);
  });

  it('resumes following after zooming, panning back to the bottom, and unzooming', async () => {
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
      const scrollport = tallScrollport(800);
      viewport.scale = 2;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      scrollUp();
      scrollport.scrollTop = 800;
      // The last marker is at the bottom edge of this nested scrollport.
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (
            this === scrollport ||
            this.classList.contains('chat-native__end')
          )
            return { top: 0, bottom: 667 } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return { top: 300, bottom: 350 } as DOMRect;
          return { top: 100, bottom: 150 } as DOMRect;
        },
      );
      viewport.scale = 1;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      const before = readsPosted();
      scrollIntoView.mockClear();
      receive('after-unzoom');
      expect(scrollIntoView).toHaveBeenCalled();
      expect(readsPosted()).toBe(before + 1);
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('keeps reading older messages after unzooming away from the bottom', async () => {
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
      const scrollport = tallScrollport(800);
      viewport.scale = 2;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      scrollUp();
      scrollport.scrollTop = 600;
      viewport.scale = 1;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      const before = readsPosted();
      scrollIntoView.mockClear();
      receive('after-unzoom-away');
      expect(scrollIntoView).not.toHaveBeenCalled();
      expect(readsPosted()).toBe(before);
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });
  for (const [name, top, gap] of [
    ['at the newest', 800, 0],
    ['100px above the newest', 700, 100],
  ] as const) {
    it(`Q1 keeps a quote jump after the keyboard closes (${name})`, async () => {
      window.matchMedia = vi.fn().mockReturnValue({ matches: true });
      withQuote();
      await openRoom();
      const scrollport = tallScrollport(top);
      placedAt(gap);
      act(() => {
        screen.getByRole('textbox').focus();
      });
      const quote = document.querySelector(
        '.chat-native__reply-quote[data-message-id="message-1"]',
      ) as HTMLElement;
      scrollIntoView.mockClear();
      scrollIntoView.mockImplementation(function (this: HTMLElement) {
        if (this.id === 'chat-message-message-1') scrollport.scrollTop = 100;
      });
      // A tap on the quote: the pointer goes down on it, the box loses focus, the click lands.
      fireEvent.pointerDown(quote);
      act(() => {
        screen.getByRole('textbox').blur();
      });
      fireEvent.click(quote);
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 50));
      });
      const afterJump = scrollport.scrollTop;
      const endBefore = endScrolls();
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 900));
      });
      expect(afterJump).toBe(100);
      expect(scrollport.scrollTop).toBe(afterJump);
      expect(endScrolls() - endBefore).toBe(0);
      expect(screen.getByRole('button', { name: JUMP })).toBeTruthy();
    });
  }

  it('Q2 a quote jump without the keyboard stays where it went (control)', async () => {
    withQuote();
    await openRoom();
    const scrollport = tallScrollport(800);
    placedAt(0);
    const quote = document.querySelector(
      '.chat-native__reply-quote[data-message-id="message-1"]',
    ) as HTMLElement;
    scrollIntoView.mockClear();
    scrollIntoView.mockImplementation(function (this: HTMLElement) {
      if (this.id === 'chat-message-message-1') scrollport.scrollTop = 100;
    });
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 950));
    });
    expect(scrollport.scrollTop).toBe(100);
  });

  it('O1 opening a room at a searched message does not mark the never shown newest one read', async () => {
    // Opened at an older message: the end of the room, and the newest message above it, are below the screen.
    placedAt(5000);
    const history = createMemoryHistory({
      initialEntries: [
        { pathname: `/chat/${ROOM}`, state: { chatMessageId: 'message-1' } },
      ],
    });
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
      await new Promise((resolve) => setTimeout(resolve, 50));
    });
    expect(readsPosted()).toBe(0);
    expect(endScrolls()).toBe(0);
    fireEvent.click(screen.getByRole('button', { name: JUMP }));
    expect(readsPosted()).toBe(1);
  });
});

// ---- Review f88a: suspicions around the cdf34d4941 changes (appended to a copy of scroll_renders helpers) ----
const wait = (ms: number) =>
  act(async () => {
    await new Promise((resolve) => setTimeout(resolve, ms));
  });
const quoteOf = (id: string) =>
  document.querySelector(
    `.chat-native__reply-quote[data-message-id="${id}"]`,
  ) as HTMLElement;
const targetScrolls = (id: string) =>
  scrollIntoView.mock.contexts.filter(
    (element) => (element as Element).id === `chat-message-${id}`,
  ).length;
const openWith = async (chatMessageId: string, text: string) => {
  const history = createMemoryHistory({
    initialEntries: [{ pathname: `/chat/${ROOM}`, state: { chatMessageId } }],
  });
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
  await screen.findByText(text);
  await wait(0);
};

describe('Review f88a', () => {
  // S1: the reader is at the newest and taps the quote of a reply to a message just above. The jump
  // centres the original; the browser's scroll event then finds the end still within 240px, so the
  // screen counts as following again. When the highlight ends 3s later, nothing new has arrived.
  for (const [name, below] of [
    ['nearby original (end 120px below)', 120],
    ['far original (end 400px below, control)', 400],
  ] as const) {
    it(`S1 a quote jump stays where it went when the highlight ends: ${name}`, async () => {
      withQuote();
      await openRoom();
      placedAt(0);
      const quote = quoteOf('message-1');
      fireEvent.pointerDown(quote);
      fireEvent.click(quote);
      await wait(50);
      expect(targetScrolls('message-1')).toBe(1);
      // The scroll event of the jump, as the browser reports it after the effect.
      placedAt(below);
      const endBefore = endScrolls();
      await wait(3200);
      expect(endScrolls() - endBefore).toBe(0);
    });
  }

  it('S1b a room opened at a searched message near the newest stays there when the highlight ends', async () => {
    await openWith('message-4', 'Message 5');
    await wait(50);
    expect(targetScrolls('message-4')).toBe(1);
    placedAt(120);
    const endBefore = endScrolls();
    await wait(3200);
    expect(endScrolls() - endBefore).toBe(0);
  });

  // S2: tap a quote, come back to the newest, tap the same quote again within its highlight.
  it('S2 tapping the same quote again within its highlight does not stop following at the newest', async () => {
    withQuote();
    await openRoom();
    placedAt(0);
    const quote = quoteOf('message-1');
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    await wait(50);
    placedAt(400);
    fireEvent.click(screen.getByRole('button', { name: JUMP }));
    placedAt(0);
    await wait(50);
    const jumpsBefore = targetScrolls('message-1');
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    await wait(50);
    // (both versions) the second tap does not move the screen
    expect(targetScrolls('message-1')).toBe(jumpsBefore);
    const readsBefore = readsPosted();
    const endBefore = endScrolls();
    receive('after-second-tap');
    await wait(50);
    expect({
      followed: endScrolls() - endBefore > 0,
      read: readsPosted() - readsBefore,
      jumpButton: screen.queryByRole('button', { name: JUMP }) !== null,
    }).toEqual({ followed: true, read: 1, jumpButton: false });
  });

  // S2b: at the newest, tap a quote whose original is already on screen below the middle: centring it
  // cannot scroll further down, so no scroll happens at all (desktop Chromium on the review server).
  it('S2b a quote to an original already shown at the newest does not stop following', async () => {
    withQuote();
    await openRoom();
    placedAt(0);
    const quote = quoteOf('message-1');
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    await wait(3300);
    const readsBefore = readsPosted();
    const endBefore = endScrolls();
    receive('after-quote-in-place');
    await wait(50);
    expect({
      followed: endScrolls() - endBefore > 0,
      read: readsPosted() - readsBefore,
      jumpButton: document.querySelector('.chat-native__jump') !== null,
    }).toEqual({ followed: true, read: 1, jumpButton: false });
  });

  it('S2b follows at the document bottom when layout padding puts the end above the viewport edge', async () => {
    withQuote();
    await openRoom();
    // Desktop review server: end at 888.75px in a 900px viewport, document at its bottom.
    const documentScrollport = document.createElement('div');
    Object.defineProperty(documentScrollport, 'scrollHeight', {
      configurable: true,
      value: window.innerHeight + 100,
    });
    documentScrollport.scrollTop = 100;
    const originalScrollingElement = Object.getOwnPropertyDescriptor(
      document,
      'scrollingElement',
    );
    Object.defineProperty(document, 'scrollingElement', {
      configurable: true,
      value: documentScrollport,
    });
    placedAt(-11.25);
    const quote = quoteOf('message-1');
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    await wait(3300);
    const readsBefore = readsPosted();
    const endBefore = endScrolls();
    receive('after-quote-with-layout-padding');
    await wait(50);
    expect({
      followed: endScrolls() - endBefore > 0,
      read: readsPosted() - readsBefore,
      jumpButton: document.querySelector('.chat-native__jump') !== null,
    }).toEqual({ followed: true, read: 1, jumpButton: false });
    if (originalScrollingElement)
      Object.defineProperty(
        document,
        'scrollingElement',
        originalScrollingElement,
      );
    else Reflect.deleteProperty(document, 'scrollingElement');
  });

  // S3: the searched message never comes (hidden for the viewer, or its author suspended, after the search).
  it('S3 a room opened at a searched message that never loads still aligns to the newest', async () => {
    await openWith('message-gone', 'Message 5');
    await wait(3500);
    expect({
      endScrolls: endScrolls(),
      jumpButton: screen.queryByRole('button', { name: JUMP }) !== null,
    }).toEqual({ endScrolls: 1, jumpButton: false });
  });

  // S5: a jump that lands while the touch keyboard is open (quote tapped first, box focused while the
  // original is still on its way), then the keyboard closes.
  it('S5 a quote jump that lands while the keyboard is open survives closing the keyboard', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    let release!: (value: { data: ReturnType<typeof messageFrom>[] }) => void;
    const older = new Promise<{ data: ReturnType<typeof messageFrom>[] }>(
      (resolve) => {
        release = resolve;
      },
    );
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages')) {
          if (options?.params?.max_id) return older;
          return Promise.resolve({
            data: Array.from({ length: 40 }, (_, i) => ({
              ...messageFrom(i + 20),
              reply_to_id: i === 39 ? 'message-1' : null,
            })),
          });
        }
        return Promise.resolve({ data: responses(url) });
      },
    );
    try {
      const history = createMemoryHistory({
        initialEntries: [`/chat/${ROOM}`],
      });
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
      await screen.findByText('Message 59');
      const scrollport = tallScrollport(800);
      placedAt(0);
      const quote = quoteOf('message-1');
      // The quote is tapped with the keyboard closed; the original is on an older page.
      fireEvent.pointerDown(quote);
      fireEvent.click(quote);
      await wait(50);
      // While it is on its way, the reader taps the box and the keyboard opens.
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      scrollIntoView.mockImplementation(function (this: HTMLElement) {
        if (this.id === 'chat-message-message-1') scrollport.scrollTop = 100;
      });
      await act(async () => {
        release({ data: Array.from({ length: 20 }, (_, i) => messageFrom(i)) });
        await older;
      });
      await wait(50);
      const afterJump = scrollport.scrollTop;
      // The keyboard closes (tap elsewhere / done).
      act(() => {
        screen.getByRole('textbox').blur();
      });
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await wait(900);
      expect({ afterJump, afterClose: scrollport.scrollTop }).toEqual({
        afterJump: 100,
        afterClose: 100,
      });
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  // Coordinator questions (expected to pass): following and reading come back after a quote or search
  // jump once the reader goes back down or taps the jump button.
  it('R1 after a quote jump with the keyboard, the jump button brings following and reading back', async () => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    withQuote();
    await openRoom();
    const scrollport = tallScrollport(800);
    placedAt(0);
    act(() => {
      screen.getByRole('textbox').focus();
    });
    scrollIntoView.mockImplementation(function (this: HTMLElement) {
      if (this.id === 'chat-message-message-1') scrollport.scrollTop = 100;
    });
    const quote = quoteOf('message-1');
    fireEvent.pointerDown(quote);
    act(() => {
      screen.getByRole('textbox').blur();
    });
    fireEvent.click(quote);
    await wait(900);
    receive('while-away');
    const readsAway = readsPosted();
    // The button reads "New messages" now; it is the same jump button.
    fireEvent.click(
      document.querySelector('.chat-native__jump') as HTMLElement,
    );
    placedAt(0);
    const readsBack = readsPosted();
    const endBefore = endScrolls();
    receive('after-return');
    await wait(50);
    expect({
      readOnReturn: readsBack - readsAway,
      followed: endScrolls() - endBefore > 0,
      readAfter: readsPosted() - readsBack,
    }).toEqual({ readOnReturn: 1, followed: true, readAfter: 1 });
  });

  it('R2 after opening at a searched message, scrolling down reads the newest and follows again', async () => {
    // Opened at an older message: the end of the room, and the newest message above it, are below the screen.
    placedAt(5000);
    await openWith('message-1', 'Message 5');
    await wait(3300);
    expect(readsPosted()).toBe(0);
    placedAt(0);
    const readsBack = readsPosted();
    const endBefore = endScrolls();
    receive('after-scroll-down');
    await wait(50);
    expect({
      readOnReturn: readsBack,
      followed: endScrolls() - endBefore > 0,
      readAfter: readsPosted() - readsBack,
    }).toEqual({ readOnReturn: 1, followed: true, readAfter: 1 });
  });
});

describe('Search targets and keyboard navigation', () => {
  it('keeps a searched target through an older-page 429 and resumes it after reconnect', async () => {
    let olderAttempts = 0;
    let newestAttempts = 0;
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages')) {
          if (options?.params?.max_id) {
            olderAttempts += 1;
            if (olderAttempts === 1)
              return Promise.reject(
                Object.assign(new Error('rate limited'), {
                  response: { status: 429, headers: { 'retry-after': '1' } },
                }),
              );
            return Promise.resolve({
              data: Array.from({ length: 20 }, (_, i) => messageFrom(i)),
            });
          }
          newestAttempts += 1;
          return Promise.resolve({
            data: Array.from({ length: 40 }, (_, i) => messageFrom(i + 20)),
          });
        }
        return Promise.resolve({ data: responses(url) });
      },
    );
    await openWith('message-1', 'Message 59');
    await wait(100);
    expect(olderAttempts).toBe(1);
    expect(endScrolls()).toBe(0);
    expect(readsPosted()).toBe(0);
    act(() => {
      emitChatStreamEvent({ event: 'chat.stream_reconnected', payload: {} });
    });
    await wait(400);
    expect(olderAttempts).toBe(1);
    expect(newestAttempts).toBe(1);
    await screen.findByText('Message 1', {}, { timeout: 4000 });
    expect(olderAttempts).toBe(2);
    expect(newestAttempts).toBe(2);
    expect(targetScrolls('message-1')).toBeGreaterThan(0);
  });

  it('retries a rate-limited searched target after the deadline without a stream event', async () => {
    let olderAttempts = 0;
    let newestAttempts = 0;
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages')) {
          if (options?.params?.max_id) {
            olderAttempts += 1;
            if (olderAttempts === 1)
              return Promise.reject(
                Object.assign(new Error('rate limited'), {
                  response: { status: 429, headers: { 'retry-after': '1' } },
                }),
              );
            return Promise.resolve({
              data: Array.from({ length: 20 }, (_, i) => messageFrom(i)),
            });
          }
          newestAttempts += 1;
          return Promise.resolve({
            data: Array.from({ length: 40 }, (_, i) => messageFrom(i + 20)),
          });
        }
        return Promise.resolve({ data: responses(url) });
      },
    );
    await openWith('message-1', 'Message 59');
    await wait(100);
    expect(endScrolls()).toBe(0);
    await wait(400);
    expect(olderAttempts).toBe(1);
    expect(newestAttempts).toBe(1);
    await screen.findByText('Message 1', {}, { timeout: 4000 });
    expect(olderAttempts).toBe(2);
    expect(newestAttempts).toBe(2);
    expect(targetScrolls('message-1')).toBeGreaterThan(0);
  });

  it('returns to the newest when the older page for a searched target fails', async () => {
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages')) {
          if (options?.params?.max_id)
            return Promise.reject(new Error('offline'));
          return Promise.resolve({
            data: Array.from({ length: 40 }, (_, i) => messageFrom(i + 20)),
          });
        }
        return Promise.resolve({ data: responses(url) });
      },
    );
    await openWith('message-1', 'Message 59');
    await wait(500);
    expect(endScrolls()).toBe(1);
    expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
  });

  it('keeps a delayed searched target after the keyboard closes', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 667,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    let release!: (value: { data: ReturnType<typeof messageFrom>[] }) => void;
    const older = new Promise<{ data: ReturnType<typeof messageFrom>[] }>(
      (resolve) => {
        release = resolve;
      },
    );
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages')) {
          if (options?.params?.max_id) return older;
          return Promise.resolve({
            data: Array.from({ length: 40 }, (_, i) => messageFrom(i + 20)),
          });
        }
        return Promise.resolve({ data: responses(url) });
      },
    );
    try {
      await openWith('message-1', 'Message 59');
      const scrollport = tallScrollport(800);
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 307;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      scrollIntoView.mockImplementation(function (this: HTMLElement) {
        if (this.id === 'chat-message-message-1') scrollport.scrollTop = 100;
      });
      await act(async () => {
        release({ data: Array.from({ length: 20 }, (_, i) => messageFrom(i)) });
        await older;
      });
      await wait(50);
      expect(scrollport.scrollTop).toBe(100);
      act(() => {
        screen.getByRole('textbox').blur();
      });
      viewport.height = 667;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await wait(900);
      expect(scrollport.scrollTop).toBe(100);
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });
});

describe('Sending while a quote is highlighted at the newest message', () => {
  it('follows my message while the highlighted quote has not moved the viewport', async () => {
    withQuote();
    await openRoom();
    placedAt(0);
    const quote = quoteOf('message-1');
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    const before = endScrolls();
    receive('own-after-quote', me);
    await wait(50);
    expect(endScrolls()).toBeGreaterThan(before);
    expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
  });
});

describe('A nested chat scrollport', () => {
  it('keeps following when a quote cannot move beyond the bottom of the scrollport', async () => {
    withQuote();
    await openRoom();
    const scrollport = tallScrollport(800);
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function (this: Element) {
        if (this === scrollport || this.classList.contains('chat-native__end'))
          return { top: 0, bottom: 400 } as DOMRect;
        if (this.classList.contains('chat-native__composer'))
          return { top: 350, bottom: 400 } as DOMRect;
        return { top: 100, bottom: 150 } as DOMRect;
      },
    );
    fireEvent.scroll(window);
    const quote = quoteOf('message-1');
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    const readsBefore = readsPosted();
    const endBefore = endScrolls();
    receive('nested-bottom');
    await wait(50);
    expect(endScrolls()).toBeGreaterThan(endBefore);
    expect(readsPosted()).toBe(readsBefore + 1);
    expect(document.querySelector('.chat-native__jump')).toBeNull();
  });
});

describe('Cancelling a pending quote jump', () => {
  const openDelayedQuote = async () => {
    let release!: (value: { data: ReturnType<typeof messageFrom>[] }) => void;
    const older = new Promise<{ data: ReturnType<typeof messageFrom>[] }>(
      (resolve) => {
        release = resolve;
      },
    );
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages')) {
          if (options?.params?.max_id) return older;
          return Promise.resolve({
            data: Array.from({ length: 40 }, (_, i) => ({
              ...messageFrom(i + 20),
              reply_to_id: i === 39 ? 'message-1' : null,
            })),
          });
        }
        return Promise.resolve({ data: responses(url) });
      },
    );
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
    await screen.findByText('Message 59');
    placedAt(0);
    const quote = quoteOf('message-1');
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    await wait(50);
    return async () => {
      await act(async () => {
        release({ data: Array.from({ length: 20 }, (_, i) => messageFrom(i)) });
        await older;
      });
      await wait(50);
    };
  };

  it('keeps an incoming message unread and stays put while seeking an older quote', async () => {
    const finish = await openDelayedQuote();
    const beforeEnds = endScrolls();
    const beforeReads = readsPosted();
    receive('incoming-during-quote-seek');
    await wait(50);
    expect(endScrolls()).toBe(beforeEnds);
    expect(readsPosted()).toBe(beforeReads);
    expect(screen.getByText('New messages')).toBeTruthy();
    await finish();
    expect(targetScrolls('message-1')).toBe(1);
  });

  it('does not jump to a delayed original after the user scrolls elsewhere', async () => {
    const finish = await openDelayedQuote();
    fireEvent.wheel(window);
    placedAt(400);
    await finish();
    expect(targetScrolls('message-1')).toBe(0);
    const before = endScrolls();
    receive('after-user-scroll');
    await wait(50);
    expect(endScrolls()).toBe(before);
  });

  it('does not jump to a delayed original after the user chooses newest', async () => {
    const finish = await openDelayedQuote();
    fireEvent.click(screen.getByRole('button', { name: JUMP }));
    placedAt(0);
    await finish();
    expect(targetScrolls('message-1')).toBe(0);
    const before = endScrolls();
    receive('after-user-newest');
    await wait(50);
    expect(endScrolls()).toBeGreaterThan(before);
  });
});

describe('A search result at the newest message', () => {
  it('reads a visible newest message when the search jump needs no movement', async () => {
    placedAt(0);
    await openWith('message-5', 'Message 5');
    await wait(50);
    expect(readsPosted()).toBe(1);
    expect(document.querySelector('.chat-native__jump')).toBeNull();
  });
});

describe('iOS visual viewport regressions', () => {
  it('does not shrink the viewport repeatedly when a small reveal is requested at the document end', async () => {
    const originalViewport = Object.getOwnPropertyDescriptor(
      window,
      'visualViewport',
    );
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const originalScrolling = Object.getOwnPropertyDescriptor(
      document,
      'scrollingElement',
    );
    const root = document.documentElement;
    const originalTop = Object.getOwnPropertyDescriptor(root, 'scrollTop');
    const originalHeight = Object.getOwnPropertyDescriptor(
      root,
      'scrollHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 549,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      writable: true,
      value: 549,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      let scrollTop = 3501;
      Object.defineProperty(document, 'scrollingElement', {
        configurable: true,
        value: root,
      });
      Object.defineProperty(root, 'scrollHeight', {
        configurable: true,
        value: 3788,
      });
      Object.defineProperty(root, 'scrollTop', {
        configurable: true,
        get: () => scrollTop,
        set: (value: number) => {
          const moved = Math.floor(value - scrollTop);
          if (moved > 0) {
            scrollTop += moved;
            viewport.height -= moved;
            viewport.offsetTop += moved;
            window.innerHeight -= moved;
          }
        },
      });
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this.classList.contains('chat-native__composer'))
            return { top: 163, bottom: 232 } as DOMRect;
          if (this.id === 'chat-message-message-5')
            return { top: 55, bottom: 148.4 } as DOMRect;
          return { top: 0, bottom: 287 } as DOMRect;
        },
      );
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 287;
      viewport.offsetTop = 262;
      window.innerHeight = 287;
      for (let i = 0; i < 5; i++)
        act(() => {
          viewport.dispatchEvent(new Event('resize'));
        });
      expect(scrollTop).toBe(3501);
      expect(viewport.height).toBe(287);
    } finally {
      cleanup();
      if (originalTop) Object.defineProperty(root, 'scrollTop', originalTop);
      else Reflect.deleteProperty(root, 'scrollTop');
      if (originalHeight)
        Object.defineProperty(root, 'scrollHeight', originalHeight);
      else Reflect.deleteProperty(root, 'scrollHeight');
      if (originalScrolling)
        Object.defineProperty(document, 'scrollingElement', originalScrolling);
      else Reflect.deleteProperty(document, 'scrollingElement');
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (originalViewport)
        Object.defineProperty(window, 'visualViewport', originalViewport);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('reveals a new message without overscrolling the keyboard viewport', async () => {
    const originalViewport = Object.getOwnPropertyDescriptor(
      window,
      'visualViewport',
    );
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const originalScrolling = Object.getOwnPropertyDescriptor(
      document,
      'scrollingElement',
    );
    const root = document.documentElement;
    const originalTop = Object.getOwnPropertyDescriptor(root, 'scrollTop');
    const originalHeight = Object.getOwnPropertyDescriptor(
      root,
      'scrollHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 549,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      writable: true,
      value: 549,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      let scrollTop = 3501;
      Object.defineProperty(document, 'scrollingElement', {
        configurable: true,
        value: root,
      });
      Object.defineProperty(root, 'scrollHeight', {
        configurable: true,
        value: 3872,
      });
      Object.defineProperty(root, 'scrollTop', {
        configurable: true,
        get: () => scrollTop,
        set: (value: number) => {
          const moved = Math.floor(value - scrollTop);
          if (moved > 0) {
            const room = Math.max(
              0,
              root.scrollHeight - window.innerHeight - scrollTop,
            );
            const overshoot = Math.max(0, moved - room);
            scrollTop += moved;
            viewport.height -= overshoot;
            viewport.offsetTop += overshoot;
            window.innerHeight -= overshoot;
          }
        },
      });
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this.classList.contains('chat-native__composer'))
            return { top: 163, bottom: 232 } as DOMRect;
          if (this.id === 'chat-message-message-5')
            return { top: 55, bottom: 232.4 - (scrollTop - 3501) } as DOMRect;
          return { top: 0, bottom: 287 } as DOMRect;
        },
      );
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 287;
      viewport.offsetTop = 262;
      window.innerHeight = 287;
      for (let i = 0; i < 5; i++)
        act(() => {
          viewport.dispatchEvent(new Event('resize'));
        });
      expect(scrollTop).toBe(3585);
      expect(viewport.height).toBe(287);
    } finally {
      cleanup();
      if (originalTop) Object.defineProperty(root, 'scrollTop', originalTop);
      else Reflect.deleteProperty(root, 'scrollTop');
      if (originalHeight)
        Object.defineProperty(root, 'scrollHeight', originalHeight);
      else Reflect.deleteProperty(root, 'scrollHeight');
      if (originalScrolling)
        Object.defineProperty(document, 'scrollingElement', originalScrolling);
      else Reflect.deleteProperty(document, 'scrollingElement');
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (originalViewport)
        Object.defineProperty(window, 'visualViewport', originalViewport);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('marks a visible message read when keyboard offsetTop is in a different coordinate space', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const root = document.documentElement;
    const originalClient = Object.getOwnPropertyDescriptor(
      root,
      'clientHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 549,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      writable: true,
      value: 549,
    });
    Object.defineProperty(root, 'clientHeight', {
      configurable: true,
      value: 549,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 287;
      viewport.offsetTop = 262;
      window.innerHeight = 287;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this.classList.contains('chat-native__composer'))
            return { top: 163, bottom: 232 } as DOMRect;
          if (this.id === 'chat-message-visible-with-keyboard')
            return { top: 69, bottom: 144 } as DOMRect;
          return { top: 0, bottom: 287 } as DOMRect;
        },
      );
      const before = readsPosted();
      receive('visible-with-keyboard');
      expect(readsPosted()).toBe(before + 1);
    } finally {
      cleanup();
      if (originalClient)
        Object.defineProperty(root, 'clientHeight', originalClient);
      else Reflect.deleteProperty(root, 'clientHeight');
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('rechecks a pending message when a keyboard viewport scroll reveals it', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 549,
      offsetTop: 0,
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
      viewport.height = 287;
      viewport.offsetTop = 262;
      let visible = false;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this.classList.contains('chat-native__composer'))
            return { top: 163, bottom: 232 } as DOMRect;
          if (this.id === 'chat-message-pending-visible')
            return visible
              ? ({ top: 69, bottom: 144 } as DOMRect)
              : ({ top: 200, bottom: 250 } as DOMRect);
          return { top: 0, bottom: 287 } as DOMRect;
        },
      );
      const before = readsPosted();
      receive('pending-visible');
      expect(readsPosted()).toBe(before);
      visible = true;
      act(() => {
        viewport.dispatchEvent(new Event('scroll'));
      });
      expect(readsPosted()).toBe(before + 1);
    } finally {
      cleanup();
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('stays away when a user scrolls beyond the follow distance with a keyboard viewport offset', async () => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 549,
      offsetTop: 0,
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
      viewport.height = 287;
      viewport.offsetTop = 262;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this.classList.contains('chat-native__end'))
            return { top: 600, bottom: 600 } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return { top: 163, bottom: 232 } as DOMRect;
          return { top: 0, bottom: 287 } as DOMRect;
        },
      );
      fireEvent.touchMove(window);
      fireEvent.scroll(window);
      expect(screen.getByRole('button', { name: JUMP })).toBeTruthy();
      const before = readsPosted();
      receive('while-reading-keyboard');
      expect(readsPosted()).toBe(before);
    } finally {
      cleanup();
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('does not overwrite another navigation position if the keyboard was never opened', async () => {
    const nav = document.createElement('div');
    nav.className = 'ui__navigation-bar';
    document.body.appendChild(nav);
    try {
      await openRoom();
      nav.style.bottom = '12px';
      cleanup();
      expect(nav.style.bottom).toBe('12px');
    } finally {
      cleanup();
      nav.remove();
    }
  });

  it('keeps the composer and mobile navigation above the visual viewport when the reader scrolls', async () => {
    const originalViewport = Object.getOwnPropertyDescriptor(
      window,
      'visualViewport',
    );
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 549,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      writable: true,
      value: 549,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    const nav = document.createElement('div');
    nav.className = 'ui__navigation-bar';
    document.body.appendChild(nav);
    try {
      await openRoom();
      nav.style.bottom = '7px';
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 287;
      viewport.offsetTop = 262;
      window.innerHeight = 287;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      viewport.offsetTop = 182;
      window.innerHeight = 367;
      act(() => {
        viewport.dispatchEvent(new Event('scroll'));
      });
      expect(nav.style.bottom).toBe('80px');
      expect(
        (
          document.querySelector('.chat-native__composer') as HTMLElement
        ).style.getPropertyValue('--chat-keyboard-lift'),
      ).toBe('80px');
      cleanup();
      expect(nav.style.bottom).toBe('7px');
    } finally {
      cleanup();
      nav.remove();
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (originalViewport)
        Object.defineProperty(window, 'visualViewport', originalViewport);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('resumes following at the visible bottom after zoom when the Safari toolbar is collapsed', async () => {
    const originalViewport = Object.getOwnPropertyDescriptor(
      window,
      'visualViewport',
    );
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const originalScrolling = Object.getOwnPropertyDescriptor(
      document,
      'scrollingElement',
    );
    const root = document.documentElement;
    const originalTop = Object.getOwnPropertyDescriptor(root, 'scrollTop');
    const originalHeight = Object.getOwnPropertyDescriptor(
      root,
      'scrollHeight',
    );
    const originalClient = Object.getOwnPropertyDescriptor(
      root,
      'clientHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 625,
      offsetTop: 1,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      writable: true,
      value: 625,
    });
    const nav = document.createElement('div');
    nav.className = 'ui__navigation-bar';
    document.body.appendChild(nav);
    try {
      await openRoom();
      Object.defineProperty(document, 'scrollingElement', {
        configurable: true,
        value: root,
      });
      Object.defineProperty(root, 'scrollHeight', {
        configurable: true,
        value: 3600,
      });
      Object.defineProperty(root, 'clientHeight', {
        configurable: true,
        value: 547,
      });
      Object.defineProperty(root, 'scrollTop', {
        configurable: true,
        writable: true,
        value: 2975,
      });
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this === nav)
            return { top: 568.5, bottom: 623.5, height: 55 } as DOMRect;
          if (this.classList.contains('chat-native__end'))
            return { top: 570.4, bottom: 570.4 } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return { top: 400, bottom: 570 } as DOMRect;
          return { top: 0, bottom: 625 } as DOMRect;
        },
      );
      viewport.scale = 2;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      fireEvent.scroll(window);
      viewport.scale = 1;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      const before = endScrolls();
      receive('after-toolbar-collapse');
      await wait(50);
      expect(endScrolls()).toBeGreaterThan(before);
    } finally {
      cleanup();
      nav.remove();
      if (originalTop) Object.defineProperty(root, 'scrollTop', originalTop);
      else Reflect.deleteProperty(root, 'scrollTop');
      if (originalHeight)
        Object.defineProperty(root, 'scrollHeight', originalHeight);
      else Reflect.deleteProperty(root, 'scrollHeight');
      if (originalClient)
        Object.defineProperty(root, 'clientHeight', originalClient);
      else Reflect.deleteProperty(root, 'clientHeight');
      if (originalScrolling)
        Object.defineProperty(document, 'scrollingElement', originalScrolling);
      else Reflect.deleteProperty(document, 'scrollingElement');
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (originalViewport)
        Object.defineProperty(window, 'visualViewport', originalViewport);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });
});

describe('Android visual viewport regressions', () => {
  it('keeps the keyboard and navigation aligned as the visual viewport moves', async () => {
    const originalViewport = Object.getOwnPropertyDescriptor(
      window,
      'visualViewport',
    );
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const root = document.documentElement;
    const originalClient = Object.getOwnPropertyDescriptor(
      root,
      'clientHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 603.4,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      writable: true,
      value: 603,
    });
    Object.defineProperty(root, 'clientHeight', {
      configurable: true,
      value: 603,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    const nav = document.createElement('div');
    nav.className = 'ui__navigation-bar';
    document.body.appendChild(nav);
    try {
      await openRoom();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 319.2;
      viewport.offsetTop = 284.2;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      expect(parseFloat(nav.style.bottom)).toBeCloseTo(0);
      viewport.offsetTop = 199.2;
      fireEvent.touchMove(window);
      act(() => {
        viewport.dispatchEvent(new Event('scroll'));
      });
      expect(parseFloat(nav.style.bottom)).toBeCloseTo(84.6);
      expect(
        parseFloat(
          (
            document.querySelector('.chat-native__composer') as HTMLElement
          ).style.getPropertyValue('--chat-keyboard-lift'),
        ),
      ).toBeCloseTo(84.6);
      cleanup();
      expect(nav.style.bottom).toBe('');
    } finally {
      cleanup();
      nav.remove();
      if (originalClient)
        Object.defineProperty(root, 'clientHeight', originalClient);
      else Reflect.deleteProperty(root, 'clientHeight');
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (originalViewport)
        Object.defineProperty(window, 'visualViewport', originalViewport);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('reads only messages within the offset visual viewport while the keyboard is open', async () => {
    const originalViewport = Object.getOwnPropertyDescriptor(
      window,
      'visualViewport',
    );
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const root = document.documentElement;
    const originalClient = Object.getOwnPropertyDescriptor(
      root,
      'clientHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 603.4,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      value: 603,
    });
    Object.defineProperty(root, 'clientHeight', {
      configurable: true,
      value: 603,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 319.2;
      viewport.offsetTop = 284.2;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this.classList.contains('chat-native__composer'))
            return { top: 479.7, bottom: 548.4 } as DOMRect;
          if (this.id === 'chat-message-above-android-viewport')
            return { top: 200, bottom: 260 } as DOMRect;
          if (this.id === 'chat-message-visible-android-viewport')
            return { top: 410.4, bottom: 465 } as DOMRect;
          return { top: 0, bottom: 603.4 } as DOMRect;
        },
      );
      const before = readsPosted();
      receive('above-android-viewport');
      expect(readsPosted()).toBe(before);
      receive('visible-android-viewport');
      expect(readsPosted()).toBe(before + 1);
    } finally {
      cleanup();
      if (originalClient)
        Object.defineProperty(root, 'clientHeight', originalClient);
      else Reflect.deleteProperty(root, 'clientHeight');
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (originalViewport)
        Object.defineProperty(window, 'visualViewport', originalViewport);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('tracks a touch-driven visual viewport pan without mistaking a small pan for reading away', async () => {
    const originalViewport = Object.getOwnPropertyDescriptor(
      window,
      'visualViewport',
    );
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const root = document.documentElement;
    const originalClient = Object.getOwnPropertyDescriptor(
      root,
      'clientHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 744.7,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      value: 744,
    });
    Object.defineProperty(root, 'clientHeight', {
      configurable: true,
      value: 744,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    try {
      await openRoom();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 420.7;
      viewport.offsetTop = 239;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this.classList.contains('chat-native__end'))
            return { top: 689.7, bottom: 689.7 } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return { top: 620.7, bottom: 689.7 } as DOMRect;
          return { top: 0, bottom: 744.7 } as DOMRect;
        },
      );
      fireEvent.touchMove(window);
      act(() => {
        viewport.dispatchEvent(new Event('scroll'));
      });
      expect(screen.queryByRole('button', { name: JUMP })).toBeNull();
      viewport.offsetTop = 0;
      fireEvent.touchMove(window);
      act(() => {
        viewport.dispatchEvent(new Event('scroll'));
      });
      expect(screen.getByRole('button', { name: JUMP })).toBeTruthy();
    } finally {
      cleanup();
      if (originalClient)
        Object.defineProperty(root, 'clientHeight', originalClient);
      else Reflect.deleteProperty(root, 'clientHeight');
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (originalViewport)
        Object.defineProperty(window, 'visualViewport', originalViewport);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });

  it('resumes following at the Pixel collapsed-toolbar bottom measured on device', async () => {
    const originalViewport = Object.getOwnPropertyDescriptor(
      window,
      'visualViewport',
    );
    const originalInner = Object.getOwnPropertyDescriptor(
      window,
      'innerHeight',
    );
    const originalScrolling = Object.getOwnPropertyDescriptor(
      document,
      'scrollingElement',
    );
    const root = document.documentElement;
    const originalTop = Object.getOwnPropertyDescriptor(root, 'scrollTop');
    const originalHeight = Object.getOwnPropertyDescriptor(
      root,
      'scrollHeight',
    );
    const originalClient = Object.getOwnPropertyDescriptor(
      root,
      'clientHeight',
    );
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 659.4,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      value: 659,
    });
    const nav = document.createElement('div');
    nav.className = 'ui__navigation-bar';
    document.body.appendChild(nav);
    try {
      await openRoom();
      Object.defineProperty(document, 'scrollingElement', {
        configurable: true,
        value: root,
      });
      Object.defineProperty(root, 'scrollHeight', {
        configurable: true,
        value: 1386,
      });
      Object.defineProperty(root, 'clientHeight', {
        configurable: true,
        value: 603,
      });
      Object.defineProperty(root, 'scrollTop', {
        configurable: true,
        writable: true,
        value: 726.5,
      });
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this === nav)
            return { top: 604.9, bottom: 659.4, height: 54.5 } as DOMRect;
          if (this.classList.contains('chat-native__end'))
            return { top: 605.8, bottom: 605.8 } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return { top: 536, bottom: 604.9 } as DOMRect;
          return { top: 0, bottom: 659.4 } as DOMRect;
        },
      );
      viewport.scale = 2;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      fireEvent.scroll(window);
      viewport.scale = 1;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      const before = endScrolls();
      receive('after-pixel-toolbar-collapse');
      await wait(50);
      expect(endScrolls()).toBeGreaterThan(before);
    } finally {
      cleanup();
      nav.remove();
      if (originalTop) Object.defineProperty(root, 'scrollTop', originalTop);
      else Reflect.deleteProperty(root, 'scrollTop');
      if (originalHeight)
        Object.defineProperty(root, 'scrollHeight', originalHeight);
      else Reflect.deleteProperty(root, 'scrollHeight');
      if (originalClient)
        Object.defineProperty(root, 'clientHeight', originalClient);
      else Reflect.deleteProperty(root, 'clientHeight');
      if (originalScrolling)
        Object.defineProperty(document, 'scrollingElement', originalScrolling);
      else Reflect.deleteProperty(document, 'scrollingElement');
      if (originalInner)
        Object.defineProperty(window, 'innerHeight', originalInner);
      else Reflect.deleteProperty(window, 'innerHeight');
      if (originalViewport)
        Object.defineProperty(window, 'visualViewport', originalViewport);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });
});

describe('A reader scrolling while the screen changes size', () => {
  // Pixel 1 (android-masto-diag t5): a finger drags down at the end with the address bar collapsed. The bar comes
  // back, the visual viewport resizes 12 times, and each resize used to pull the page back to the end.
  const dragWhileResizing = async (endsAt: number, arrives?: string) => {
    const original = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 659.4,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    try {
      await openRoom();
      placedAt(659.4 - window.innerHeight);
      scrollIntoView.mockClear();
      fireEvent.touchMove(window);
      for (const height of [640, 620, 603.4]) {
        viewport.height = height;
        act(() => {
          viewport.dispatchEvent(new Event('resize'));
        });
        fireEvent.touchMove(window);
      }
      if (arrives) receive(arrives);
      const whileDragging = endScrolls();
      placedAt(603.4 - window.innerHeight + endsAt);
      await wait(250);
      return { whileDragging, afterDrag: endScrolls() - whileDragging };
    } finally {
      if (original) Object.defineProperty(window, 'visualViewport', original);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  };

  it('does not pull the reader back while they drag, nor once they stop', async () => {
    expect(await dragWhileResizing(70)).toEqual({
      whileDragging: 0,
      afterDrag: 0,
    });
  });

  it('shows a message that came in during the drag once they stop near the newest', async () => {
    expect(await dragWhileResizing(70, 'during-drag')).toEqual({
      whileDragging: 0,
      afterDrag: 1,
    });
  });

  it('leaves a reader who stopped away from the newest where they are', async () => {
    expect(await dragWhileResizing(400, 'during-drag-away')).toEqual({
      whileDragging: 0,
      afterDrag: 0,
    });
  });
});
