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
    vi.stubGlobal('window', {
      Notification: NotificationMock,
      focus: vi.fn(),
      location: { assign: vi.fn() },
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
});
