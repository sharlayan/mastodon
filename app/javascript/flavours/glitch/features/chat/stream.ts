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

export const showChatDesktopNotification = (payload: unknown) => {
  if (!('Notification' in window) || Notification.permission !== 'granted')
    return;

  const message = payload as Partial<ChatNotificationPayload>;
  if (!message.conversation_id || !message.account) return;

  const name = message.account.display_name || message.account.acct;
  const notification = new Notification(`${name} · Chat`, {
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
