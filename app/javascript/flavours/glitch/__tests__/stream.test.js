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
      sockets.push(this);
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
    vi.useRealTimers();
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
