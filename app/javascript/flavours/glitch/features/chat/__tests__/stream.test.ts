// @vitest-environment node

import { showChatDesktopNotification } from '../stream';

const payload = {
  id: '10',
  conversation_id: '20',
  content: 'Hello',
  account: {
    display_name: 'Alice',
    acct: 'alice',
    avatar: 'https://example.com/avatar.png',
  },
};

describe('Chat stream connection', () => {
  it('announces reconnections but not the first connection', async () => {
    vi.resetModules();
    const stream = await import('../stream');
    const listener = vi.fn();
    const unsubscribe = stream.subscribeChatStream(listener);

    stream.handleChatStreamConnected();
    expect(listener).not.toHaveBeenCalled();

    stream.handleChatStreamConnected();
    expect(listener).toHaveBeenCalledWith({
      event: stream.CHAT_STREAM_RECONNECTED,
      payload: {},
    });
    unsubscribe();
  });

  it('announces each poll made while the stream is down', async () => {
    vi.resetModules();
    const stream = await import('../stream');
    const listener = vi.fn();
    const unsubscribe = stream.subscribeChatStream(listener);

    stream.handleChatStreamPolled();

    expect(listener).toHaveBeenCalledWith({
      event: stream.CHAT_STREAM_RECONNECTED,
      payload: {},
    });
    unsubscribe();
  });
});

describe('Chat desktop notifications', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('does not notify without browser permission', () => {
    const constructor = vi.fn();
    function NotificationMock(...args: unknown[]) {
      constructor(...args);
    }
    NotificationMock.permission = 'denied';
    vi.stubGlobal('Notification', NotificationMock);
    vi.stubGlobal('window', { Notification: NotificationMock });

    showChatDesktopNotification(payload);

    expect(constructor).not.toHaveBeenCalled();
  });

  it('shows a conversation-scoped notification for an incoming message', () => {
    const addEventListener = vi.fn();
    const close = vi.fn();
    const constructor = vi.fn();
    class NotificationMock {
      static permission = 'granted';

      addEventListener = addEventListener;
      close = close;

      constructor(...args: unknown[]) {
        constructor(...args);
      }
    }
    vi.stubGlobal('Notification', NotificationMock);
    vi.stubGlobal('document', { visibilityState: 'visible' });
    vi.stubGlobal('window', {
      Notification: NotificationMock,
      focus: vi.fn(),
      location: { assign: vi.fn(), pathname: '/home' },
    });

    showChatDesktopNotification(payload);

    expect(constructor).toHaveBeenCalledWith('Alice · Chat', {
      body: 'Hello',
      icon: 'https://example.com/avatar.png',
      tag: 'chat-20',
    });
    expect(addEventListener).toHaveBeenCalledWith(
      'click',
      expect.any(Function),
    );
  });

  it('keeps the advanced layout when the notification is opened', () => {
    const addEventListener = vi.fn();
    const assign = vi.fn();
    class NotificationMock {
      static permission = 'granted';

      addEventListener = addEventListener;
      close = vi.fn();
    }
    vi.stubGlobal('Notification', NotificationMock);
    vi.stubGlobal('document', { visibilityState: 'hidden' });
    vi.stubGlobal('window', {
      Notification: NotificationMock,
      focus: vi.fn(),
      location: { assign, pathname: '/deck/home' },
    });

    showChatDesktopNotification(payload);

    const click = addEventListener.mock.calls.find(
      ([event]) => event === 'click',
    )?.[1] as (() => void) | undefined;
    click?.();

    expect(assign).toHaveBeenCalledWith('/deck/chat/20');
  });

  it('opens the single-column chat path outside the advanced layout', () => {
    const addEventListener = vi.fn();
    const assign = vi.fn();
    class NotificationMock {
      static permission = 'granted';

      addEventListener = addEventListener;
      close = vi.fn();
    }
    vi.stubGlobal('Notification', NotificationMock);
    vi.stubGlobal('document', { visibilityState: 'hidden' });
    vi.stubGlobal('window', {
      Notification: NotificationMock,
      focus: vi.fn(),
      location: { assign, pathname: '/home' },
    });

    showChatDesktopNotification(payload);

    const click = addEventListener.mock.calls.find(
      ([event]) => event === 'click',
    )?.[1] as (() => void) | undefined;
    click?.();

    expect(assign).toHaveBeenCalledWith('/chat/20');
  });

  describe('while the conversation is on screen', () => {
    const setUp = (pathname: string, visibilityState: string) => {
      const constructor = vi.fn();
      class NotificationMock {
        static permission = 'granted';

        addEventListener = vi.fn();
        close = vi.fn();

        constructor(...args: unknown[]) {
          constructor(...args);
        }
      }
      vi.stubGlobal('Notification', NotificationMock);
      vi.stubGlobal('document', { visibilityState });
      vi.stubGlobal('window', {
        Notification: NotificationMock,
        focus: vi.fn(),
        location: { assign: vi.fn(), pathname },
      });
      return constructor;
    };

    it('stays quiet in the visible conversation', () => {
      const constructor = setUp('/chat/20', 'visible');

      showChatDesktopNotification(payload);

      expect(constructor).not.toHaveBeenCalled();
    });

    it('stays quiet in the visible conversation in the advanced layout', () => {
      const constructor = setUp('/deck/chat/20', 'visible');

      showChatDesktopNotification(payload);

      expect(constructor).not.toHaveBeenCalled();
    });

    it('notifies when that conversation is in a background tab', () => {
      const constructor = setUp('/chat/20', 'hidden');

      showChatDesktopNotification(payload);

      expect(constructor).toHaveBeenCalled();
    });
  });
});
