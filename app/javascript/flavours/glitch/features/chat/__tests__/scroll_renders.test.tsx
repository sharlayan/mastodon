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

await vi.hoisted(() => import('../testing/match_media'));

const api = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  patch: vi.fn(),
  delete: vi.fn(),
}));
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
const originalAway = (top = -600, bottom = top + 50) => {
  const measure = vi
    .spyOn(Element.prototype, 'getBoundingClientRect')
    .getMockImplementation();
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
    function (this: Element) {
      if (this.id === 'chat-message-message-1')
        return { top, bottom } as DOMRect;
      return measure ? measure.call(this) : ({} as DOMRect);
    },
  );
};

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
      originalAway();
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
      originalAway();
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
    originalAway();
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
  for (const [name, below, original] of [
    ['nearby original (end 120px below)', 120, [260, 310]],
    ['far original (end 400px below, control)', 400, [-600, -550]],
  ] as const) {
    it(`S1 a quote jump stays where it went when the highlight ends: ${name}`, async () => {
      withQuote();
      await openRoom();
      placedAt(0);
      originalAway(...original);
      const quote = quoteOf('message-1');
      fireEvent.pointerDown(quote);
      fireEvent.click(quote);
      await wait(50);
      expect(targetScrolls('message-1')).toBe(1);
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

  it('S3 a room opened at a searched message that never loads still aligns to the newest', async () => {
    await openWith('message-gone', 'Message 5');
    await wait(3500);
    expect({
      endScrolls: endScrolls(),
      jumpButton: screen.queryByRole('button', { name: JUMP }) !== null,
    }).toEqual({ endScrolls: 1, jumpButton: false });
  });

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
      fireEvent.pointerDown(quote);
      fireEvent.click(quote);
      await wait(50);
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

  it('R1 after a quote jump with the keyboard, the jump button brings following and reading back', async () => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    withQuote();
    await openRoom();
    const scrollport = tallScrollport(800);
    placedAt(0);
    originalAway();
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
      fireEvent.touchEnd(window);
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

const androidViewport = () => {
  const originals = {
    viewport: Object.getOwnPropertyDescriptor(window, 'visualViewport'),
    inner: Object.getOwnPropertyDescriptor(window, 'innerHeight'),
    client: Object.getOwnPropertyDescriptor(
      document.documentElement,
      'clientHeight',
    ),
  };
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
  Object.defineProperty(document.documentElement, 'clientHeight', {
    configurable: true,
    value: 744,
  });
  window.matchMedia = vi.fn().mockReturnValue({ matches: true });
  const nav = document.createElement('div');
  nav.className = 'ui__navigation-bar';
  document.body.appendChild(nav);
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
    function (this: Element) {
      if (this === nav)
        return { top: 689.7, bottom: 744.7, height: 55 } as DOMRect;
      if (this.classList.contains('chat-native__end'))
        return { top: 690.6, bottom: 690.6 } as DOMRect;
      if (this.classList.contains('chat-native__composer'))
        return { top: 620.7, bottom: 689.7 } as DOMRect;
      if (this.classList.contains('chat-native'))
        return { top: 0, bottom: 744 } as DOMRect;
      return { top: 550.7, bottom: 605.6 } as DOMRect;
    },
  );
  const move = (height: number, offsetTop: number, event: string) => {
    viewport.height = height;
    viewport.offsetTop = offsetTop;
    act(() => {
      viewport.dispatchEvent(new Event(event));
    });
  };
  const restore = () => {
    cleanup();
    nav.remove();
    for (const [target, key, descriptor] of [
      [window, 'visualViewport', originals.viewport],
      [window, 'innerHeight', originals.inner],
      [document.documentElement, 'clientHeight', originals.client],
    ] as const) {
      if (descriptor) Object.defineProperty(target, key, descriptor);
      else Reflect.deleteProperty(target, key);
    }
  };
  return { nav, move, restore };
};

describe('Android keyboard on f35f1ec', () => {
  it('raises nothing while Chrome brings the visual viewport down to the composer, then follows a drag', async () => {
    const android = androidViewport();
    try {
      await openRoom();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      android.move(420.7, 0, 'resize');
      const whileOpening = parseFloat(android.nav.style.bottom || '0');
      android.move(420.7, 150, 'scroll');
      android.move(420.7, 324, 'scroll');
      const rested = parseFloat(android.nav.style.bottom || '0');
      fireEvent.touchMove(window);
      android.move(420.7, 238.3, 'scroll');
      expect({
        whileOpening,
        rested,
        dragged: Math.round(parseFloat(android.nav.style.bottom) * 10) / 10,
      }).toEqual({ whileOpening: 0, rested: 0, dragged: 85 });
    } finally {
      android.restore();
    }
  });

  it('follows and reads again when a quote to an original already shown is tapped with the keyboard open', async () => {
    withQuote();
    const android = androidViewport();
    try {
      await openRoom();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      android.move(420.7, 0, 'resize');
      android.move(420.7, 324, 'scroll');
      scrollIntoView.mockImplementation(function (this: HTMLElement) {
        if (this.id === 'chat-message-message-1')
          android.move(420.7, 246, 'scroll');
      });
      const quote = quoteOf('message-1');
      fireEvent.pointerDown(quote);
      act(() => {
        screen.getByRole('textbox').blur();
      });
      fireEvent.click(quote);
      await wait(50);
      android.move(744.7, 0, 'resize');
      await wait(1000);
      const readsBefore = readsPosted();
      const endBefore = endScrolls();
      receive('after-keyboard-quote');
      await wait(50);
      expect({
        followed: endScrolls() - endBefore > 0,
        read: readsPosted() - readsBefore,
        jumpButton: document.querySelector('.chat-native__jump') !== null,
      }).toEqual({ followed: true, read: 1, jumpButton: false });
    } finally {
      android.restore();
    }
  });
});

describe('Review f35f', () => {
  it('P1 a finger resting on the screen after a short drag is not pulled by an arriving message', async () => {
    await openRoom();
    placedAt(85);
    scrollIntoView.mockClear();
    fireEvent.touchStart(window);
    fireEvent.touchMove(window);
    fireEvent.scroll(window);
    await wait(400);
    receive('resting-newest');
    await wait(50);
    const whileResting = endScrolls();
    fireEvent.touchEnd(window);
    await wait(250);
    expect({ whileResting, afterLifting: endScrolls() }).toEqual({
      whileResting: 0,
      afterLifting: 1,
    });
  });

  it('P2 a real viewport shrink right after a keyboard reveal still reveals the last message', async () => {
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
      let scrollTop = 3000;
      const assignments: number[] = [];
      Object.defineProperty(document, 'scrollingElement', {
        configurable: true,
        value: root,
      });
      Object.defineProperty(root, 'scrollHeight', {
        configurable: true,
        value: 9000,
      });
      Object.defineProperty(root, 'scrollTop', {
        configurable: true,
        get: () => scrollTop,
        set: (value: number) => {
          assignments.push(value - scrollTop);
          scrollTop = value;
        },
      });
      let lastBottomAtStart = 147;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          const composerTop = viewport.height - 124;
          if (this.classList.contains('chat-native__composer'))
            return { top: composerTop, bottom: composerTop + 69 } as DOMRect;
          if (this.classList.contains('chat-native__end'))
            return {
              top: composerTop + 69,
              bottom: composerTop + 70,
            } as DOMRect;
          if (this.id.startsWith('chat-message-'))
            return {
              top: 0,
              bottom: lastBottomAtStart - (scrollTop - 3000),
            } as DOMRect;
          return { top: 0, bottom: viewport.height } as DOMRect;
        },
      );
      act(() => {
        screen.getByRole('textbox').focus();
      });
      viewport.height = 287;
      window.innerHeight = 287;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      assignments.length = 0;
      lastBottomAtStart = 240 + (scrollTop - 3000);
      receive('under-composer');
      await wait(20);
      const revealed = [...assignments];
      viewport.height = 247;
      window.innerHeight = 247;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await wait(20);
      const afterShrink = assignments.slice(revealed.length);
      expect({ revealed, afterShrink }).toEqual({
        revealed: [93],
        afterShrink: [40],
      });
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

  it('D2 keeps the reader’s place when older messages come in above (review server: +3,050px)', async () => {
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages'))
          return Promise.resolve({
            data: options?.params?.max_id
              ? Array.from({ length: 37 }, (_, i) => messageFrom(i))
              : Array.from({ length: 40 }, (_, i) => messageFrom(i + 37)),
          });
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
    await screen.findByText('Message 76');
    await wait(0);
    const scrollport = tallScrollport(0);
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function (this: Element) {
        if (this.classList.contains('chat-native__end'))
          return { top: 5000, bottom: 5000 } as DOMRect;
        if (this.classList.contains('chat-native'))
          return { top: 0, bottom: 768 } as DOMRect;
        if (this.classList.contains('chat-native__composer'))
          return { top: 700, bottom: 768 } as DOMRect;
        if (this.id === 'chat-message-message-37')
          return document.getElementById('chat-message-message-36')
            ? ({ top: 3209, bottom: 3259 } as DOMRect)
            : ({ top: 159, bottom: 209 } as DOMRect);
        return { top: 100, bottom: 150 } as DOMRect;
      },
    );
    fireEvent.scroll(window);
    expect(screen.getByRole('button', { name: JUMP })).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText('Message 0');
    expect(scrollport.scrollTop).toBe(3050);
  });
});

describe('iOS keyboard on f35f1ec', () => {
  it('does not raise the composer when the box is focused while reading a little up (SE 3, 136pt)', async () => {
    const originals = {
      viewport: Object.getOwnPropertyDescriptor(window, 'visualViewport'),
      inner: Object.getOwnPropertyDescriptor(window, 'innerHeight'),
      client: Object.getOwnPropertyDescriptor(
        document.documentElement,
        'clientHeight',
      ),
    };
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 547,
      offsetTop: 0,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      writable: true,
      value: 547,
    });
    Object.defineProperty(document.documentElement, 'clientHeight', {
      configurable: true,
      value: 547,
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
      viewport.height = 320.5;
      viewport.offsetTop = 226.5;
      window.innerHeight = 385;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      const focused = parseFloat(nav.style.bottom || '0');
      viewport.offsetTop = 149.5;
      window.innerHeight = 398;
      act(() => {
        viewport.dispatchEvent(new Event('scroll'));
      });
      expect({
        focused,
        dragged: parseFloat(nav.style.bottom),
      }).toEqual({ focused: 0, dragged: 77 });
    } finally {
      cleanup();
      nav.remove();
      for (const [target, key, descriptor] of [
        [window, 'visualViewport', originals.viewport],
        [window, 'innerHeight', originals.inner],
        [document.documentElement, 'clientHeight', originals.client],
      ] as const) {
        if (descriptor) Object.defineProperty(target, key, descriptor);
        else Reflect.deleteProperty(target, key);
      }
    }
  });
});

describe('iOS keyboard on ddbad17ba3', () => {
  const geo = {
    end: { top: 494.8, bottom: 494.8 },
    composer: { top: 425, bottom: 494 },
    nav: { top: 494, bottom: 549 },
    last: { top: 355, bottom: 410 },
  };
  let scrollTop = 0;
  let scrollTops: number[] = [];
  const iphone = () => {
    const root = document.documentElement;
    const saved = {
      viewport: Object.getOwnPropertyDescriptor(window, 'visualViewport'),
      inner: Object.getOwnPropertyDescriptor(window, 'innerHeight'),
      scrollY: Object.getOwnPropertyDescriptor(window, 'scrollY'),
      client: Object.getOwnPropertyDescriptor(root, 'clientHeight'),
      top: Object.getOwnPropertyDescriptor(root, 'scrollTop'),
      height: Object.getOwnPropertyDescriptor(root, 'scrollHeight'),
      scrolling: Object.getOwnPropertyDescriptor(document, 'scrollingElement'),
    };
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 549,
      offsetTop: 0,
      pageTop: 0,
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
    Object.defineProperty(window, 'scrollY', {
      configurable: true,
      writable: true,
      value: 0,
    });
    Object.defineProperty(root, 'clientHeight', {
      configurable: true,
      value: 549,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
    const nav = document.createElement('div');
    nav.className = 'ui__navigation-bar';
    document.body.appendChild(nav);
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function (this: Element) {
        if (this.classList.contains('chat-native__end'))
          return geo.end as DOMRect;
        if (this.classList.contains('chat-native__composer'))
          return geo.composer as DOMRect;
        if (this.classList.contains('ui__navigation-bar'))
          return { ...geo.nav, height: 55 } as DOMRect;
        if (this.id.startsWith('chat-message-live')) return geo.last as DOMRect;
        return { top: -2000, bottom: -1950 } as DOMRect;
      },
    );
    const page = (
      at: {
        innerHeight?: number;
        height?: number;
        offsetTop?: number;
        scrollY: number;
      },
      events: ('resize' | 'scroll' | 'window')[] = ['scroll'],
    ) => {
      if (at.innerHeight !== undefined) window.innerHeight = at.innerHeight;
      if (at.height !== undefined) viewport.height = at.height;
      if (at.offsetTop !== undefined) viewport.offsetTop = at.offsetTop;
      window.scrollY = at.scrollY;
      viewport.pageTop = at.scrollY;
      scrollTop = at.scrollY;
      act(() => {
        for (const type of events)
          if (type === 'window') fireEvent.scroll(window);
          else viewport.dispatchEvent(new Event(type));
      });
    };
    const measurePage = (height: number) => {
      scrollTops = [];
      const total = () =>
        height +
        (parseFloat(
          document.querySelector<HTMLElement>('.chat-native__end')?.style
            .marginBottom ?? '',
        ) || 0);
      Object.defineProperty(document, 'scrollingElement', {
        configurable: true,
        value: root,
      });
      Object.defineProperty(root, 'scrollHeight', {
        configurable: true,
        get: total,
      });
      Object.defineProperty(root, 'scrollTop', {
        configurable: true,
        get: () => scrollTop,
        set: (value: number) => {
          scrollTops.push(value);
          scrollTop = Math.min(value, total() - window.innerHeight);
        },
      });
    };
    const restore = () => {
      cleanup();
      nav.remove();
      for (const [target, key, descriptor] of [
        [window, 'visualViewport', saved.viewport],
        [window, 'innerHeight', saved.inner],
        [window, 'scrollY', saved.scrollY],
        [root, 'clientHeight', saved.client],
        [root, 'scrollTop', saved.top],
        [root, 'scrollHeight', saved.height],
        [document, 'scrollingElement', saved.scrolling],
      ] as const) {
        if (descriptor) Object.defineProperty(target, key, descriptor);
        else Reflect.deleteProperty(target, key);
      }
    };
    return { viewport, nav, page, measurePage, restore };
  };
  const drag = (move: () => void) => {
    fireEvent.touchStart(document.body);
    fireEvent.touchMove(document.body);
    move();
    fireEvent.touchEnd(document.body);
  };

  beforeEach(() => {
    Object.assign(geo, {
      end: { top: 494.8, bottom: 494.8 },
      composer: { top: 425, bottom: 494 },
      nav: { top: 494, bottom: 549 },
      last: { top: 355, bottom: 410 },
    });
  });

  it('keeps the composer over the keyboard through a flick (b-k2s3: 262px, raised by 0 on ddbad17)', async () => {
    const device = iphone();
    try {
      await openRoom();
      device.page({ scrollY: 1695 });
      act(() => {
        screen.getByRole('textbox').focus();
      });
      device.page(
        { innerHeight: 287, height: 287, offsetTop: 262, scrollY: 1957 },
        ['resize'],
      );
      drag(() => {
        device.page({ innerHeight: 367, offsetTop: 182, scrollY: 1877 });
        device.page({ innerHeight: 447, offsetTop: 102, scrollY: 1797 });
      });
      const dragged = device.nav.style.bottom;
      device.page({ innerHeight: 549, offsetTop: -0.5, scrollY: 1611 }, [
        'scroll',
        'resize',
        'window',
      ]);
      expect({ dragged, flicked: device.nav.style.bottom }).toEqual({
        dragged: '160px',
        flicked: '262.5px',
      });
    } finally {
      device.restore();
    }
  });

  it('does not start following, nor pull to a new message, after reading a little with the keyboard open far up (b-fk)', async () => {
    const device = iphone();
    try {
      await openRoom();
      device.measurePage(2627);
      geo.end = { top: 951.6, bottom: 951.6 };
      drag(() => {
        device.page({ scrollY: 1621 }, ['window']);
      });
      await wait(300);
      act(() => {
        screen.getByRole('textbox').focus();
      });
      Object.assign(geo, {
        composer: { top: 162.5, bottom: 231.5 },
        nav: { top: 231.5, bottom: 286.5 },
        end: { top: 634.6, bottom: 634.6 },
      });
      device.page({ height: 287, offsetTop: 262, scrollY: 1938 }, [
        'resize',
        'window',
      ]);
      geo.end = { top: 684.6, bottom: 684.6 };
      drag(() => {
        device.page({ offsetTop: 212, scrollY: 1888 }, ['scroll', 'window']);
      });
      await wait(300);
      const shownAway = document.querySelector('.chat-native__jump') !== null;
      scrollTops = [];
      geo.last = { top: 650, bottom: 690 };
      receive('live-far');
      await wait(50);
      expect({ shownAway, scrolled: scrollTops }).toEqual({
        shownAway: true,
        scrolled: [],
      });
    } finally {
      device.restore();
    }
  });

  it('shows the newest before the keyboard opens when the box is focused a little up (b-a130: 117pt)', async () => {
    const device = iphone();
    try {
      await openRoom();
      device.measurePage(2957);
      geo.end = { top: 611.1, bottom: 611.1 };
      geo.last = { top: 471.3, bottom: 526.1 };
      receive('live-near-newest');
      drag(() => {
        device.page({ scrollY: 2292 }, ['window']);
      });
      await wait(300);
      scrollTops = [];
      act(() => {
        screen.getByRole('textbox').focus();
      });
      expect(scrollTop).toBe(2408);
    } finally {
      device.restore();
    }
  });
});

describe('iOS 18 keyboard on a7566004ab', () => {
  it('makes room under the keyboard and shows the newest when Safari scrolls from where the page was (a130)', async () => {
    const root = document.documentElement;
    const saved = {
      viewport: Object.getOwnPropertyDescriptor(window, 'visualViewport'),
      inner: Object.getOwnPropertyDescriptor(window, 'innerHeight'),
      scrollY: Object.getOwnPropertyDescriptor(window, 'scrollY'),
      client: Object.getOwnPropertyDescriptor(root, 'clientHeight'),
      top: Object.getOwnPropertyDescriptor(root, 'scrollTop'),
      height: Object.getOwnPropertyDescriptor(root, 'scrollHeight'),
      scrolling: Object.getOwnPropertyDescriptor(document, 'scrollingElement'),
    };
    const viewport = Object.assign(new EventTarget(), {
      scale: 1,
      height: 547,
      offsetTop: 0,
      pageTop: 1545,
    });
    let top = 1545;
    const geo = {
      end: { top: 493, bottom: 493 },
      composer: { top: 423, bottom: 492 },
      nav: { top: 492, bottom: 547 },
      last: { top: 354, bottom: 408 },
    };
    const total = () =>
      2092 +
      (parseFloat(
        document.querySelector<HTMLElement>('.chat-native__end')?.style
          .marginBottom ?? '',
      ) || 0);
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: viewport,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      writable: true,
      value: 547,
    });
    Object.defineProperty(window, 'scrollY', {
      configurable: true,
      get: () => top,
    });
    Object.defineProperty(root, 'clientHeight', {
      configurable: true,
      value: 547,
    });
    window.matchMedia = vi.fn().mockReturnValue({ matches: true });
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
        get: total,
      });
      Object.defineProperty(root, 'scrollTop', {
        configurable: true,
        get: () => top,
        set: (value: number) => {
          top = Math.min(value, total() - window.innerHeight);
          viewport.pageTop = top;
        },
      });
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          const by = window.innerHeight < 547 ? top - 1725 : 0;
          const at = (r: { top: number; bottom: number }) =>
            ({ top: r.top - by, bottom: r.bottom - by }) as DOMRect;
          if (this.classList.contains('chat-native__end')) return at(geo.end);
          if (this.classList.contains('chat-native__composer'))
            return geo.composer as DOMRect;
          if (this.classList.contains('ui__navigation-bar'))
            return { ...geo.nav, height: 55 } as DOMRect;
          if (this.id === 'chat-message-message-5') return at(geo.last);
          return { top: -2000, bottom: -1950 } as DOMRect;
        },
      );
      Object.assign(geo, {
        end: { top: 611, bottom: 611 },
        last: { top: 472, bottom: 526 },
      });
      fireEvent.touchStart(document.body);
      fireEvent.touchMove(document.body);
      top = 1427;
      viewport.pageTop = 1427;
      fireEvent.scroll(window);
      fireEvent.touchEnd(document.body);
      await wait(300);
      act(() => {
        screen.getByRole('textbox').focus();
      });
      const atFocus = top;
      top = 1725;
      viewport.pageTop = 1725;
      viewport.height = 320.5;
      viewport.offsetTop = 226.5;
      window.innerHeight = 367;
      Object.assign(geo, {
        composer: { top: 196.5, bottom: 265.5 },
        nav: { top: 265.5, bottom: 320.5 },
        end: { top: 313, bottom: 313 },
        last: { top: 174, bottom: 228 },
      });
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
        viewport.dispatchEvent(new Event('scroll'));
      });
      const end = document.querySelector<HTMLElement>('.chat-native__end');
      const shown = {
        room: end?.style.marginBottom,
        scrollTop: top,
        lastBottom: geo.last.bottom - (top - 1725),
      };
      act(() => {
        screen.getByRole('textbox').blur();
      });
      window.innerHeight = 547;
      viewport.height = 547;
      viewport.offsetTop = 0;
      act(() => {
        viewport.dispatchEvent(new Event('resize'));
      });
      await wait(800);
      expect({
        atFocus,
        ...shown,
        closedRoom: end?.style.marginBottom,
      }).toEqual({
        atFocus: 1545,
        room: '46.5px',
        scrollTop: 1771.5,
        lastBottom: 181.5,
        closedRoom: '',
      });
    } finally {
      cleanup();
      nav.remove();
      for (const [target, key, descriptor] of [
        [window, 'visualViewport', saved.viewport],
        [window, 'innerHeight', saved.inner],
        [window, 'scrollY', saved.scrollY],
        [root, 'clientHeight', saved.client],
        [root, 'scrollTop', saved.top],
        [root, 'scrollHeight', saved.height],
        [document, 'scrollingElement', saved.scrolling],
      ] as const) {
        if (descriptor) Object.defineProperty(target, key, descriptor);
        else Reflect.deleteProperty(target, key);
      }
    }
  });
});

describe('A room opened at a searched message, on ddbad17ba3', () => {
  const open = async (chatMessageId: string) => {
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
    await screen.findByText('Message 5');
    await wait(50);
    return history;
  };

  it('is opened at the newest after reloading once the searched message was reached (343 kept on ddbad17)', async () => {
    placedAt(5000);
    const history = await open('message-1');
    expect(targetScrolls('message-1')).toBe(1);
    expect({
      pathname: history.location.pathname,
      state: history.location.state,
      entries: history.length,
    }).toEqual({ pathname: `/chat/${ROOM}`, state: {}, entries: 1 });
  });

  it('forgets it when the reader scrolls down to the newest before it is reached', async () => {
    placedAt(5000);
    const history = createMemoryHistory({
      initialEntries: [
        { pathname: `/chat/${ROOM}`, state: { chatMessageId: 'message-1' } },
      ],
    });
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages'))
          return options?.params?.max_id
            ? new Promise(() => undefined)
            : Promise.resolve({
                data: Array.from({ length: 40 }, (_, i) => messageFrom(i + 20)),
              });
        return Promise.resolve({ data: responses(url) });
      },
    );
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
    await wait(50);
    expect(history.location.state).toEqual({ chatMessageId: 'message-1' });
    fireEvent.touchMove(document.body);
    placedAt(0);
    expect(history.location.state).toEqual({});
  });
});

describe('A quote whose original is in full view, on ddbad17ba3', () => {
  it('highlights it where it is and keeps following (iPhone S2b: centred 63px and let go of the newest)', async () => {
    withQuote();
    await openRoom();
    placedAt(0);
    const quote = quoteOf('message-1');
    fireEvent.pointerDown(quote);
    fireEvent.click(quote);
    await wait(50);
    const highlighted = document
      .getElementById('chat-message-message-1')
      ?.classList.contains('chat-native__message--highlighted');
    const readsBefore = readsPosted();
    const endBefore = endScrolls();
    receive('after-shown-quote');
    await wait(50);
    expect({
      jumped: targetScrolls('message-1'),
      highlighted,
      jumpButton: document.querySelector('.chat-native__jump') !== null,
      followed: endScrolls() - endBefore > 0,
      read: readsPosted() - readsBefore,
    }).toEqual({
      jumped: 0,
      highlighted: true,
      jumpButton: false,
      followed: true,
      read: 1,
    });
  });
});

const phonePage = ({
  innerHeight,
  clientHeight,
  scrollHeight,
  scrollTop,
}: {
  innerHeight: number;
  clientHeight: number;
  scrollHeight: number;
  scrollTop: number;
}) => {
  const root = document.documentElement;
  const saved = {
    viewport: Object.getOwnPropertyDescriptor(window, 'visualViewport'),
    inner: Object.getOwnPropertyDescriptor(window, 'innerHeight'),
    scrollY: Object.getOwnPropertyDescriptor(window, 'scrollY'),
    client: Object.getOwnPropertyDescriptor(root, 'clientHeight'),
    top: Object.getOwnPropertyDescriptor(root, 'scrollTop'),
    height: Object.getOwnPropertyDescriptor(root, 'scrollHeight'),
    scrolling: Object.getOwnPropertyDescriptor(document, 'scrollingElement'),
  };
  const state = {
    top: scrollTop,
    client: clientHeight,
    writes: [] as number[],
  };
  const viewport = Object.assign(new EventTarget(), {
    scale: 1,
    height: innerHeight,
    offsetTop: 0,
    pageTop: scrollTop,
  });
  const margin = () =>
    parseFloat(
      document.querySelector<HTMLElement>('.chat-native__end')?.style
        .marginBottom ?? '',
    ) || 0;
  Object.defineProperty(window, 'visualViewport', {
    configurable: true,
    value: viewport,
  });
  Object.defineProperty(window, 'innerHeight', {
    configurable: true,
    writable: true,
    value: innerHeight,
  });
  Object.defineProperty(window, 'scrollY', {
    configurable: true,
    get: () => state.top,
  });
  Object.defineProperty(root, 'clientHeight', {
    configurable: true,
    get: () => state.client,
  });
  window.matchMedia = vi.fn().mockReturnValue({ matches: true });
  const nav = document.createElement('div');
  nav.className = 'ui__navigation-bar';
  document.body.appendChild(nav);
  const scrollWithPage = () => {
    Object.defineProperty(document, 'scrollingElement', {
      configurable: true,
      value: root,
    });
    Object.defineProperty(root, 'scrollHeight', {
      configurable: true,
      get: () => scrollHeight + margin(),
    });
    Object.defineProperty(root, 'scrollTop', {
      configurable: true,
      get: () => state.top,
      set: (value: number) => {
        state.writes.push(value);
        state.top = Math.min(
          value,
          scrollHeight + margin() - window.innerHeight,
        );
        viewport.pageTop = state.top + viewport.offsetTop;
      },
    });
  };
  const restore = () => {
    cleanup();
    nav.remove();
    for (const [target, key, descriptor] of [
      [window, 'visualViewport', saved.viewport],
      [window, 'innerHeight', saved.inner],
      [window, 'scrollY', saved.scrollY],
      [root, 'clientHeight', saved.client],
      [root, 'scrollTop', saved.top],
      [root, 'scrollHeight', saved.height],
      [document, 'scrollingElement', saved.scrolling],
    ] as const) {
      if (descriptor) Object.defineProperty(target, key, descriptor);
      else Reflect.deleteProperty(target, key);
    }
  };
  return { state, viewport, nav, margin, scrollWithPage, restore };
};

describe('Focusing the box at the newest with the browser bar collapsed (review 730b E1)', () => {
  interface Collapsed {
    innerHeight: number;
    clientHeight: number;
    height: number;
    offsetTop: number;
    scrollHeight: number;
    scrollTop: number;
    composer: { top: number; bottom: number };
    nav: { top: number; bottom: number; height: number };
    end: number;
  }
  const collapsed: [string, Collapsed][] = [
    [
      'Pixel URL bar, kcol-1',
      {
        innerHeight: 659,
        clientHeight: 603,
        height: 659.4,
        offsetTop: 0,
        scrollHeight: 1926,
        scrollTop: 1266.7,
        composer: { top: 535.7, bottom: 604.4 },
        nav: { top: 604.9, bottom: 659.4, height: 54.5 },
        end: 605.6,
      },
    ],
    [
      'iPhone SE 2 toolbar, b-c11',
      {
        innerHeight: 589,
        clientHeight: 549,
        height: 589,
        offsetTop: 0,
        scrollHeight: 2237,
        scrollTop: 1648,
        composer: { top: 465, bottom: 534 },
        nav: { top: 534, bottom: 589, height: 55 },
        end: 534.6,
      },
    ],
    [
      'iPhone SE 3 toolbar, b-c11',
      {
        innerHeight: 625,
        clientHeight: 547,
        height: 625,
        offsetTop: 1,
        scrollHeight: 2120,
        scrollTop: 1496,
        composer: { top: 499.5, bottom: 568.5 },
        nav: { top: 568.5, bottom: 623.5, height: 55 },
        end: 570,
      },
    ],
  ];
  for (const [name, at] of collapsed)
    it(`makes no room below the end at the focus (${name}: 56/40/79px on 730b)`, async () => {
      const page = phonePage(at);
      try {
        await openRoom();
        page.scrollWithPage();
        page.viewport.height = at.height;
        page.viewport.offsetTop = at.offsetTop;
        vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
          function (this: Element) {
            if (this === page.nav) return at.nav as DOMRect;
            if (this.classList.contains('chat-native__end'))
              return { top: at.end, bottom: at.end } as DOMRect;
            if (this.classList.contains('chat-native__composer'))
              return at.composer as DOMRect;
            return { top: 100, bottom: 150 } as DOMRect;
          },
        );
        act(() => {
          screen.getByRole('textbox').focus();
        });
        await wait(50);
        expect(page.margin()).toBe(0);
      } finally {
        page.restore();
      }
    });

  it('leaves no band between the composer and the navigation bar as Chrome opens its keyboard (Pixel kcol-1: 55.3px)', async () => {
    const page = phonePage({
      innerHeight: 659,
      clientHeight: 603,
      scrollHeight: 1926,
      scrollTop: 1266.7,
    });
    try {
      await openRoom();
      page.scrollWithPage();
      page.viewport.height = 659.4;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this === page.nav)
            return { top: 604.9, bottom: 659.4, height: 54.5 } as DOMRect;
          if (this.classList.contains('chat-native__end'))
            return {
              top: 605.6 - page.margin(),
              bottom: 605.6 - page.margin(),
            } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return {
              top: 535.7 - page.margin(),
              bottom: 604.4 - page.margin(),
            } as DOMRect;
          return { top: 100, bottom: 150 } as DOMRect;
        },
      );
      act(() => {
        screen.getByRole('textbox').focus();
      });
      page.state.client = 659;
      for (const [height, offsetTop, type] of [
        [351.7, 0, 'resize'],
        [375.2, 4.2, 'scroll'],
        [375.2, 99.8, 'scroll'],
        [375.2, 284.2, 'scroll'],
      ] as const) {
        page.viewport.height = height;
        page.viewport.offsetTop = offsetTop;
        page.viewport.pageTop = page.state.top + offsetTop;
        act(() => {
          page.viewport.dispatchEvent(new Event(type));
        });
      }
      await wait(50);
      const composer = document
        .querySelector('.chat-native__composer')
        ?.getBoundingClientRect();
      expect({
        room: page.margin(),
        band: composer ? Math.round((604.9 - composer.bottom) * 10) / 10 : null,
      }).toEqual({ room: 0, band: 0.5 });
    } finally {
      page.restore();
    }
  });
});

describe('A quote highlighted where it is with the keyboard open, away from the newest (review 730b J1)', () => {
  it('goes back to where the reader was when the keyboard closes (SE 3 b-aw1: 298px off on 730b)', async () => {
    withQuote();
    const page = phonePage({
      innerHeight: 547,
      clientHeight: 547,
      scrollHeight: 2092,
      scrollTop: 1545,
    });
    const geo = {
      end: 493 as number,
      composer: { top: 423, bottom: 492 },
      nav: { top: 492, bottom: 547 },
      original: { top: -400, bottom: -350 },
    };
    try {
      await openRoom();
      page.scrollWithPage();
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this === page.nav) return { ...geo.nav, height: 55 } as DOMRect;
          if (this.classList.contains('chat-native__end'))
            return { top: geo.end, bottom: geo.end } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return geo.composer as DOMRect;
          if (this.id === 'chat-message-message-1')
            return geo.original as DOMRect;
          return { top: -2000, bottom: -1950 } as DOMRect;
        },
      );
      geo.end = 910;
      page.state.top = 1128;
      page.viewport.pageTop = 1128;
      fireEvent.scroll(window);
      expect(screen.queryByRole('button', { name: JUMP })).not.toBeNull();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      page.state.top = 1426;
      Object.assign(page.viewport, {
        height: 320.5,
        offsetTop: 226.5,
        pageTop: 1426,
      });
      Object.assign(geo, {
        end: 612,
        composer: { top: 196.5, bottom: 265.5 },
        nav: { top: 265.5, bottom: 320.5 },
        original: { top: 40, bottom: 90 },
      });
      act(() => {
        page.viewport.dispatchEvent(new Event('resize'));
        page.viewport.dispatchEvent(new Event('scroll'));
      });
      fireEvent.scroll(window);
      await wait(50);
      page.state.writes = [];
      const quote = quoteOf('message-1');
      fireEvent.pointerDown(quote);
      act(() => {
        screen.getByRole('textbox').blur();
      });
      fireEvent.click(quote);
      await wait(50);
      const highlighted = document
        .getElementById('chat-message-message-1')
        ?.classList.contains('chat-native__message--highlighted');
      const atTap = page.state.top;
      Object.assign(page.viewport, {
        height: 547,
        offsetTop: 0,
        pageTop: 1426,
      });
      Object.assign(geo, {
        end: 612,
        composer: { top: 423, bottom: 492 },
        nav: { top: 492, bottom: 547 },
        original: { top: 40, bottom: 90 },
      });
      act(() => {
        page.viewport.dispatchEvent(new Event('resize'));
      });
      await wait(800);
      expect({
        jumped: targetScrolls('message-1'),
        highlighted,
        atTap,
        writes: page.state.writes,
        closedAt: page.state.top,
      }).toEqual({
        jumped: 0,
        highlighted: true,
        atTap: 1426,
        writes: [1128],
        closedAt: 1128,
      });
    } finally {
      page.restore();
    }
  });
});

describe('Android on f496c2c262 and review f496', () => {
  const tabsBar = () => {
    const bar = document.createElement('div');
    bar.className = 'tabs-bar__wrapper';
    document.body.prepend(bar);
    return bar;
  };

  for (const [name, at] of [
    [
      'Pixel s7h-1',
      {
        innerHeight: 603,
        height: 603.4,
        scrollHeight: 1878,
        scrollTop: 1136.8,
        header: 50.8,
        nav: { top: 548.9, bottom: 603.4, height: 54.5 },
        composer: { top: 479.7, bottom: 548.4 },
        end: 687.5,
        original: { top: 31.6, bottom: 66 },
      },
    ],
    [
      'Galaxy s7h-1',
      {
        innerHeight: 744,
        height: 744.7,
        scrollHeight: 1924,
        scrollTop: 1179.3,
        header: 51,
        nav: { top: 689.7, bottom: 744.7, height: 55 },
        composer: { top: 620.7, bottom: 689.7 },
        end: 690.6,
        original: { top: 27.7, bottom: 62.6 },
      },
    ],
  ] as const) {
    for (const under of [true, false])
      it(`2 ${under ? 'goes to an original partly under the column header' : 'control: highlights one in full view below it'} (${name})`, async () => {
        withQuote();
        const page = phonePage({
          innerHeight: at.innerHeight,
          clientHeight: at.innerHeight,
          scrollHeight: at.scrollHeight,
          scrollTop: at.scrollTop,
        });
        const bar = tabsBar();
        const original = under
          ? at.original
          : { top: at.header + 10, bottom: at.header + 44 };
        try {
          await openRoom();
          page.scrollWithPage();
          page.viewport.height = at.height;
          vi.spyOn(
            Element.prototype,
            'getBoundingClientRect',
          ).mockImplementation(function (this: Element) {
            if (this === page.nav) return at.nav as DOMRect;
            if (this === bar)
              return {
                top: 0,
                bottom: at.header,
                height: at.header,
              } as DOMRect;
            if (this.classList.contains('chat-native__end'))
              return { top: at.end, bottom: at.end } as DOMRect;
            if (this.classList.contains('chat-native__composer'))
              return at.composer as DOMRect;
            if (this.id === 'chat-message-message-1')
              return original as DOMRect;
            return { top: 140, bottom: 188 } as DOMRect;
          });
          fireEvent.scroll(window);
          scrollIntoView.mockClear();
          const quote = quoteOf('message-1');
          fireEvent.pointerDown(quote);
          fireEvent.click(quote);
          await wait(50);
          expect({
            jumped: targetScrolls('message-1'),
            highlighted: document
              .getElementById('chat-message-message-1')
              ?.classList.contains('chat-native__message--highlighted'),
          }).toEqual({ jumped: under ? 1 : 0, highlighted: true });
        } finally {
          bar.remove();
          page.restore();
        }
      });
  }

  it('3 gives the place back when the keyboard goes as Chrome shows its bar again (Pixel kupc-3)', async () => {
    const page = phonePage({
      innerHeight: 659,
      clientHeight: 603,
      scrollHeight: 1834,
      scrollTop: 902.1,
    });
    const geo = {
      nav: { top: 604.9, bottom: 659.4, height: 54.5 },
      composer: { top: 535.7, bottom: 604.4 },
      end: 878.2,
    };
    try {
      await openRoom();
      page.scrollWithPage();
      page.viewport.height = 659.4;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this === page.nav) return geo.nav as DOMRect;
          if (this.classList.contains('chat-native__end'))
            return { top: geo.end, bottom: geo.end } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return geo.composer as DOMRect;
          return { top: -2000, bottom: -1950 } as DOMRect;
        },
      );
      fireEvent.scroll(window);
      expect(screen.queryByRole('button', { name: JUMP })).not.toBeNull();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      page.state.top = 1033.9;
      page.state.client = 659;
      Object.assign(page.viewport, { height: 375.2, offsetTop: 284.2 });
      geo.end = 746.4;
      act(() => {
        page.viewport.dispatchEvent(new Event('resize'));
        window.dispatchEvent(new Event('resize'));
        page.viewport.dispatchEvent(new Event('scroll'));
      });
      fireEvent.scroll(window);
      await wait(50);
      page.state.writes = [];
      Object.assign(page.viewport, { height: 603.4, offsetTop: 0 });
      act(() => {
        page.viewport.dispatchEvent(new Event('resize'));
      });
      window.innerHeight = 603;
      page.state.client = 603;
      Object.assign(geo, {
        nav: { top: 548.9, bottom: 603.4, height: 54.5 },
        composer: { top: 479.7, bottom: 548.4 },
        end: 782.8,
      });
      act(() => {
        window.dispatchEvent(new Event('resize'));
      });
      await wait(400);
      expect({
        focused: document.activeElement === screen.getByRole('textbox'),
        writes: page.state.writes,
        closedAt: page.state.top,
      }).toEqual({ focused: true, writes: [902.1], closedAt: 902.1 });
    } finally {
      page.restore();
    }
  });

  interface Geo {
    end: number;
    composer: { top: number; bottom: number };
    nav: { top: number; bottom: number };
    message: (element: Element) => DOMRect | undefined;
  }
  const focusAway = async (page: ReturnType<typeof phonePage>, geo: Geo) => {
    page.scrollWithPage();
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function (this: Element) {
        if (this === page.nav) return { ...geo.nav, height: 55 } as DOMRect;
        if (this.classList.contains('chat-native__end'))
          return { top: geo.end, bottom: geo.end } as DOMRect;
        if (this.classList.contains('chat-native__composer'))
          return geo.composer as DOMRect;
        return geo.message(this) ?? ({ top: -2000, bottom: -1950 } as DOMRect);
      },
    );
    geo.end = 910;
    page.state.top = 1128;
    page.viewport.pageTop = 1128;
    fireEvent.scroll(window);
    expect(screen.queryByRole('button', { name: JUMP })).not.toBeNull();
    act(() => {
      screen.getByRole('textbox').focus();
    });
    page.state.top = 1426;
    Object.assign(page.viewport, {
      height: 320.5,
      offsetTop: 226.5,
      pageTop: 1426,
    });
    Object.assign(geo, {
      end: 612,
      composer: { top: 196.5, bottom: 265.5 },
      nav: { top: 265.5, bottom: 320.5 },
    });
    act(() => {
      page.viewport.dispatchEvent(new Event('resize'));
      page.viewport.dispatchEvent(new Event('scroll'));
    });
    fireEvent.scroll(window);
    await wait(50);
    page.state.writes = [];
  };
  const closeKeyboard = async (
    page: ReturnType<typeof phonePage>,
    geo: Geo,
  ) => {
    act(() => {
      screen.getByRole('textbox').blur();
    });
    Object.assign(page.viewport, { height: 547, offsetTop: 0 });
    Object.assign(geo, {
      composer: { top: 423, bottom: 492 },
      nav: { top: 492, bottom: 547 },
    });
    act(() => {
      page.viewport.dispatchEvent(new Event('resize'));
    });
    await wait(800);
  };

  it('J1′ goes back to where the reader was after the same quote is pressed again (SE 3 b-aw1)', async () => {
    withQuote();
    const page = phonePage({
      innerHeight: 547,
      clientHeight: 547,
      scrollHeight: 2092,
      scrollTop: 1545,
    });
    let original = { top: 40, bottom: 90 };
    const geo: Geo = {
      end: 493,
      composer: { top: 423, bottom: 492 },
      nav: { top: 492, bottom: 547 },
      message: (element) =>
        element.id === 'chat-message-message-1'
          ? (original as DOMRect)
          : undefined,
    };
    try {
      await openRoom();
      await focusAway(page, geo);
      const quote = quoteOf('message-1');
      fireEvent.pointerDown(quote);
      fireEvent.click(quote);
      await wait(50);
      original = { top: 170, bottom: 220 };
      fireEvent.pointerDown(quote);
      fireEvent.click(quote);
      await wait(50);
      const highlighted = document
        .getElementById('chat-message-message-1')
        ?.classList.contains('chat-native__message--highlighted');
      const atPress = page.state.top;
      await closeKeyboard(page, geo);
      expect({
        jumped: targetScrolls('message-1'),
        highlighted,
        atPress,
        writes: page.state.writes,
        closedAt: page.state.top,
      }).toEqual({
        jumped: 0,
        highlighted: true,
        atPress: 1426,
        writes: [1128],
        closedAt: 1128,
      });
    } finally {
      page.restore();
    }
  });

  it('P4 goes back to where the reader was, older messages and all, after a quote never found (SE 3 b-aw1)', async () => {
    api.get.mockImplementation(
      (url: string, options?: { params?: { max_id?: string } }) => {
        if (url.endsWith('/messages'))
          return Promise.resolve({
            data: options?.params?.max_id
              ? Array.from({ length: 10 }, (_, index) => messageFrom(index))
              : Array.from({ length: 40 }, (_, index) => ({
                  ...messageFrom(index + 20),
                  reply_to_id: index === 39 ? 'gone' : null,
                })),
          });
        return Promise.resolve({ data: responses(url) });
      },
    );
    const page = phonePage({
      innerHeight: 547,
      clientHeight: 547,
      scrollHeight: 2092,
      scrollTop: 1545,
    });
    const geo: Geo = {
      end: 493,
      composer: { top: 423, bottom: 492 },
      nav: { top: 492, bottom: 547 },
      message: (element) => {
        if (element.id !== 'chat-message-message-20') return undefined;
        const top = document.getElementById('chat-message-message-0')
          ? -500
          : -600;
        return { top, bottom: top + 50 } as DOMRect;
      },
    };
    try {
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
            <Router
              history={createMemoryHistory({
                initialEntries: [`/chat/${ROOM}`],
              })}
            >
              <Route path='/chat/:conversationId?/:view?'>
                <Chat />
              </Route>
            </Router>
          </IdentityContext.Provider>
        </IntlProvider>,
      );
      await screen.findByText('Message 59');
      await wait(0);
      await focusAway(page, geo);
      const quote = quoteOf('gone');
      fireEvent.pointerDown(quote);
      fireEvent.click(quote);
      await wait(50);
      const older = document.getElementById('chat-message-message-0') !== null;
      const sought = page.state.top;
      await closeKeyboard(page, geo);
      expect({
        older,
        sought,
        jump: screen.queryByRole('button', { name: JUMP }) !== null,
        writes: page.state.writes,
        closedAt: page.state.top,
      }).toEqual({
        older: true,
        sought: 1526,
        jump: true,
        writes: [1526, 1228],
        closedAt: 1228,
      });
    } finally {
      page.restore();
    }
  });
});

describe('The keyboard brought back by a tap on the box still focused (Android on f496c2c262)', () => {
  it('3 gives the place back again after the keyboard comes back with a tap and goes (Pixel kupc-6)', async () => {
    const page = phonePage({
      innerHeight: 603,
      clientHeight: 603,
      scrollHeight: 1914,
      scrollTop: 945.5,
    });
    const geo = {
      nav: { top: 548.9, bottom: 603.4, height: 54.5 },
      composer: { top: 479.7, bottom: 548.4 },
      end: 915.1,
    };
    const keyboard = (scrollTop: number) => {
      page.state.top = scrollTop;
      Object.assign(page.viewport, { height: 319.2, offsetTop: 284.2 });
      act(() => {
        page.viewport.dispatchEvent(new Event('resize'));
        page.viewport.dispatchEvent(new Event('scroll'));
      });
      fireEvent.scroll(window);
    };
    const backKey = () => {
      Object.assign(page.viewport, { height: 603.4, offsetTop: 0 });
      act(() => {
        page.viewport.dispatchEvent(new Event('resize'));
        window.dispatchEvent(new Event('resize'));
      });
    };
    try {
      await openRoom();
      page.scrollWithPage();
      page.viewport.height = 603.4;
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this === page.nav) return geo.nav as DOMRect;
          if (this.classList.contains('chat-native__end'))
            return { top: geo.end, bottom: geo.end } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return geo.composer as DOMRect;
          return { top: -2000, bottom: -1950 } as DOMRect;
        },
      );
      fireEvent.scroll(window);
      const box = screen.getByRole('textbox');
      act(() => {
        box.focus();
      });
      keyboard(1016.4);
      await wait(50);
      backKey();
      await wait(400);
      const first = [...page.state.writes];
      page.state.writes = [];
      fireEvent.pointerDown(box);
      keyboard(1016.4);
      await wait(50);
      backKey();
      await wait(400);
      expect({
        focused: document.activeElement === box,
        first,
        second: page.state.writes,
        closedAt: page.state.top,
      }).toEqual({
        focused: true,
        first: [945.5],
        second: [945.5],
        closedAt: 945.5,
      });
    } finally {
      page.restore();
    }
  });
});

describe('A keyboard that shortens the page with it (regression kb on d25d9cf06b)', () => {
  it('3 gives the place back when it goes', async () => {
    const page = phonePage({
      innerHeight: 667,
      clientHeight: 667,
      scrollHeight: 4000,
      scrollTop: 2733,
    });
    const geo = {
      nav: { top: 612, bottom: 667, height: 55 },
      composer: { top: 543, bottom: 612 },
      end: 1213,
    };
    const resize = (height: number) => {
      window.innerHeight = height;
      page.state.client = height;
      page.viewport.height = height;
      Object.assign(geo, {
        nav: { top: height - 55, bottom: height, height: 55 },
        composer: { top: height - 124, bottom: height - 55 },
      });
      act(() => {
        page.viewport.dispatchEvent(new Event('resize'));
        window.dispatchEvent(new Event('resize'));
      });
    };
    try {
      await openRoom();
      page.scrollWithPage();
      vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
        function (this: Element) {
          if (this === page.nav) return geo.nav as DOMRect;
          if (this.classList.contains('chat-native__end'))
            return { top: geo.end, bottom: geo.end } as DOMRect;
          if (this.classList.contains('chat-native__composer'))
            return geo.composer as DOMRect;
          return { top: -2000, bottom: -1950 } as DOMRect;
        },
      );
      fireEvent.scroll(window);
      expect(screen.queryByRole('button', { name: JUMP })).not.toBeNull();
      act(() => {
        screen.getByRole('textbox').focus();
      });
      await wait(100);
      resize(367);
      await wait(400);
      page.state.top += 420;
      geo.end -= 420;
      fireEvent.scroll(window);
      await wait(100);
      page.state.writes = [];
      receive('kb-reading');
      await wait(300);
      resize(667);
      act(() => {
        screen.getByRole('textbox').blur();
      });
      await wait(900);
      expect({ writes: page.state.writes, closedAt: page.state.top }).toEqual({
        writes: [2733],
        closedAt: 2733,
      });
    } finally {
      page.restore();
    }
  });
});
