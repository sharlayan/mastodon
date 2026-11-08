import {
  CHAT_STREAM_RECONNECTED,
  subscribeChatStream,
} from 'flavours/glitch/features/chat/stream';

import { connectUserStream, connectCommunityStream } from '../streaming';

interface StreamCallbacks {
  onConnect: () => void;
  onDisconnect: () => void;
  onSubscribed?: () => void;
}
type StreamSetup = (dispatch: unknown, getState: unknown) => StreamCallbacks;

const streamSetup = vi.hoisted<{ current: StreamSetup | null }>(() => ({
  current: null,
}));

vi.mock('flavours/glitch/stream', () => ({
  connectStream: (_channel: string, _params: unknown, setup: StreamSetup) => {
    streamSetup.current = setup;
    return () => undefined;
  },
}));

const open = (connect: () => unknown) => {
  connect();
  const dispatch = vi.fn(() => Promise.resolve());
  const getState = vi.fn(() => ({ getIn: () => 'en' }));
  if (!streamSetup.current) throw new Error('The stream was not connected');
  return streamSetup.current(dispatch, getState);
};

describe('Chat while the stream is down', () => {
  const listener = vi.fn();
  let unsubscribe: () => void;

  beforeEach(() => {
    vi.useFakeTimers();
    listener.mockClear();
    unsubscribe = subscribeChatStream(listener);
  });

  afterEach(() => {
    unsubscribe();
    vi.useRealTimers();
  });

  it('refreshes chat once the server says the user stream is subscribed, not before', () => {
    const callbacks = open(connectUserStream);

    callbacks.onConnect();
    expect(listener).not.toHaveBeenCalled();

    callbacks.onSubscribed?.();

    expect(listener).toHaveBeenCalledTimes(1);
    expect(listener).toHaveBeenCalledWith({
      event: CHAT_STREAM_RECONNECTED,
      payload: {},
    });
  });

  it('does not refresh chat when the connection comes back before polling began', () => {
    const callbacks = open(connectUserStream);

    callbacks.onDisconnect();
    callbacks.onConnect();
    expect(listener).not.toHaveBeenCalled();

    callbacks.onSubscribed?.();

    expect(listener).toHaveBeenCalledTimes(1);
  });

  it('refreshes chat on every poll of the user stream', async () => {
    const callbacks = open(connectUserStream);

    callbacks.onDisconnect();
    await vi.advanceTimersByTimeAsync(40_000);
    expect(listener).toHaveBeenCalledWith({
      event: CHAT_STREAM_RECONNECTED,
      payload: {},
    });

    listener.mockClear();
    await vi.advanceTimersByTimeAsync(40_000);
    expect(listener).toHaveBeenCalled();
  });

  it('stops once the stream is back', async () => {
    const callbacks = open(connectUserStream);

    callbacks.onDisconnect();
    await vi.advanceTimersByTimeAsync(40_000);
    callbacks.onConnect();
    listener.mockClear();
    await vi.advanceTimersByTimeAsync(120_000);

    expect(listener).toHaveBeenCalledTimes(0);
  });

  it('leaves other streams out of it', async () => {
    const callbacks = open(connectCommunityStream);

    expect(callbacks.onSubscribed).toBeUndefined();
    callbacks.onConnect();
    callbacks.onDisconnect();
    await vi.advanceTimersByTimeAsync(120_000);

    expect(listener).not.toHaveBeenCalled();
  });
});
