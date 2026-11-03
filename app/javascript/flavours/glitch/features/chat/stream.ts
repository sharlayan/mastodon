export interface ChatStreamEvent {
  event: string;
  payload: unknown;
}

interface ChatNotificationPayload {
  id: string;
  conversation_id: string;
  content: string | null;
  account: {
    display_name: string;
    acct: string;
    avatar?: string;
  };
}

type Listener = (event: ChatStreamEvent) => void;

const listeners = new Set<Listener>();

export const emitChatStreamEvent = (event: ChatStreamEvent) => {
  listeners.forEach((listener) => {
    listener(event);
  });
};

export const showChatDesktopNotification = (
  payload: unknown,
  title = 'Chat',
) => {
  if (!('Notification' in window) || Notification.permission !== 'granted')
    return;

  const message = payload as Partial<ChatNotificationPayload>;
  if (!message.conversation_id || !message.account) return;

  // The advanced layout serves the same screen under /deck. A background tab
  // is not on screen, even when it is showing this conversation.
  const path = window.location.pathname.replace(/^\/deck(?=\/)/, '');
  if (
    path === `/chat/${message.conversation_id}` &&
    document.visibilityState !== 'hidden'
  )
    return;

  const name = message.account.display_name || message.account.acct;
  const notification = new Notification(`${name} · ${title}`, {
    body: message.content ?? '',
    icon: message.account.avatar,
    tag: `chat-${message.conversation_id}`,
  });
  notification.addEventListener('click', () => {
    window.focus();
    window.location.assign(`/chat/${message.conversation_id}`);
    notification.close();
  });
};

export const subscribeChatStream = (listener: Listener) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};
