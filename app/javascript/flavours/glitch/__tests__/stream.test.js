import { Map as ImmutableMap } from 'immutable';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const sockets = [];

vi.mock('@gamestdio/websocket', () => {
  class FakeWebSocketClient {
    static OPEN = 1;

    constructor(url) {
      this.url = url;
      this.readyState = FakeWebSocketClient.OPEN;
      this.sent = [];
      this.opens = 0;
      this.backoff = {
        attempts: 0,
        delay: 100,
        onReady: () => {
          this.opens += 1;
        },
        backoff() {
          setTimeout(this.onReady, Math.floor(Math.random() * (2 ** ++this.attempts) * this.delay));
        },
      };
      sockets.push(this);
    }

    drop() {
      this.onclose?.({ code: 1006 });
      this.backoff.backoff();
    }

    send(message) {
      this.sent.push(JSON.parse(message));
    }

    receive(payload) {
      this.onmessage({ data: JSON.stringify(payload) });
    }
  }

  return { default: FakeWebSocketClient };
});

vi.mock('flavours/glitch/initial_state', () => ({
  getAccessToken: () => 'token',
  me: '1',
}));

const getState = () => ({
  meta: ImmutableMap({ streaming_api_base_url: 'wss://streaming.test' }),
});

const connect = async (onReceive = () => undefined) => {
  const { connectStream } = await import('flavours/glitch/stream');

  const disconnect = connectStream('user', {}, () => ({
    onConnect: () => undefined,
    onDisconnect: () => undefined,
    onReceive,
  }))(() => undefined, getState);

  const socket = sockets[sockets.length - 1];
  socket.onopen();

  return { disconnect, socket };
};

describe('shared streaming connection', () => {
  beforeEach(() => {
    vi.resetModules();
    vi.useFakeTimers();
    sockets.length = 0;
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('caps the reconnect delay for a long-lived page', async () => {
    vi.spyOn(Math, 'random').mockReturnValue(0.999);
    const { socket, disconnect } = await connect();

    socket.backoff.attempts = 15;
    socket.drop();

    await vi.advanceTimersByTimeAsync(30000);

    expect(socket.opens).toBe(1);
    disconnect();
  });

  it('resets the reconnect backoff after a successful connection', async () => {
    const { socket, disconnect } = await connect();

    socket.drop();
    socket.drop();
    socket.drop();
    expect(socket.backoff.attempts).toBe(3);

    socket.onopen();

    expect(socket.backoff.attempts).toBe(0);
    disconnect();
  });

  it('dispatches events to the matching subscription', async () => {
    const onReceive = vi.fn();
    const { socket, disconnect } = await connect(onReceive);

    socket.receive({ stream: ['user'], event: 'notification', payload: '{}' });

    expect(onReceive).toHaveBeenCalledTimes(1);
    disconnect();
  });

  it('retries a subscription the server rejected instead of failing silently', async () => {
    const onReceive = vi.fn();
    const { socket, disconnect } = await connect(onReceive);

    expect(socket.sent).toEqual([{ type: 'subscribe', stream: 'user' }]);

    socket.receive({ error: 'Access token does not cover required scopes', status: 401, stream: ['user'] });

    expect(onReceive).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(2000);

    expect(socket.sent).toEqual([
      { type: 'subscribe', stream: 'user' },
      { type: 'subscribe', stream: 'user' },
    ]);

    socket.receive({ stream: ['user'], event: 'notification', payload: '{}' });
    expect(onReceive).toHaveBeenCalledTimes(1);

    disconnect();
  });

  it('gives up retrying after a bounded number of attempts', async () => {
    const { socket, disconnect } = await connect();

    for (let attempt = 0; attempt < 8; attempt++) {
      socket.receive({ error: 'Access token does not cover required scopes', status: 401, stream: ['user'] });
      await vi.advanceTimersByTimeAsync(120000);
    }

    expect(socket.sent).toHaveLength(6);
    disconnect();
  });

  it('asks for a subscription to be answered only by a subscriber that waits for the answer', async () => {
    const { connectStream } = await import('flavours/glitch/stream');
    const onSubscribed = vi.fn();
    connectStream('user', {}, () => ({
      onConnect: () => undefined,
      onDisconnect: () => undefined,
      onReceive: () => undefined,
      onSubscribed,
    }))(() => undefined, getState);
    connectStream('public:local', {}, () => ({
      onConnect: () => undefined,
      onDisconnect: () => undefined,
      onReceive: () => undefined,
    }))(() => undefined, getState);
    connectStream('hashtag', { tag: 'chat' }, () => ({
      onConnect: () => undefined,
      onDisconnect: () => undefined,
      onReceive: () => undefined,
    }))(() => undefined, getState);

    const socket = sockets[sockets.length - 1];
    socket.onopen();

    expect(socket.sent).toEqual(expect.arrayContaining([
      { type: 'subscribe', stream: 'user', ack: true },
      { type: 'subscribe', stream: 'public:local' },
      { type: 'subscribe', stream: 'hashtag', tag: 'chat' },
    ]));
    expect(socket.sent).toHaveLength(3);
  });

  it('gives the answer to the subscriber and not as an event of the stream', async () => {
    const { connectStream } = await import('flavours/glitch/stream');
    const onConnect = vi.fn();
    const onReceive = vi.fn();
    const onSubscribed = vi.fn();
    connectStream('user', {}, () => ({
      onConnect,
      onDisconnect: () => undefined,
      onReceive,
      onSubscribed,
    }))(() => undefined, getState);
    const socket = sockets[sockets.length - 1];

    socket.onopen();
    expect(onConnect).toHaveBeenCalledTimes(1);
    expect(onSubscribed).not.toHaveBeenCalled();

    socket.receive({ stream: ['user'], event: 'subscribed' });

    expect(onSubscribed).toHaveBeenCalledTimes(1);
    expect(onReceive).not.toHaveBeenCalled();
  });

  it('counts a separate connection as subscribed when it opens, as nothing can answer there', async () => {
    const { connectStream } = await import('flavours/glitch/stream');
    const onSubscribed = vi.fn();
    const sources = [];
    vi.stubGlobal('EventSource', class {
      constructor() {
        sources.push(this);
      }

      addEventListener() {
        return undefined;
      }
    });
    const eventSourceState = () => ({
      meta: ImmutableMap({ streaming_api_base_url: 'https://streaming.test' }),
    });

    connectStream('user', {}, () => ({
      onConnect: () => undefined,
      onDisconnect: () => undefined,
      onReceive: () => undefined,
      onSubscribed,
    }))(() => undefined, eventSourceState);
    expect(onSubscribed).not.toHaveBeenCalled();

    sources[0].onopen();

    expect(onSubscribed).toHaveBeenCalledTimes(1);
    vi.unstubAllGlobals();
  });

  it('ignores a control message that carries no stream', async () => {
    const onReceive = vi.fn();
    const { socket, disconnect } = await connect(onReceive);

    expect(() => {
      socket.receive({ error: 'Invalid request', status: 400 });
    }).not.toThrow();

    expect(onReceive).not.toHaveBeenCalled();
    disconnect();
  });
});
