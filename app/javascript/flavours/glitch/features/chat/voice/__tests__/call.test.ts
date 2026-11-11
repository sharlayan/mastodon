import type { VoiceCredentials } from '../api';

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
const dispatch = vi.hoisted(() => vi.fn());
const rooms = vi.hoisted(() => [] as FakeRoomShape[]);

interface FakeRoomShape {
  options: unknown;
  emit: (event: string, ...args: unknown[]) => void;
  connect: ReturnType<typeof vi.fn>;
  disconnect: ReturnType<typeof vi.fn>;
  localParticipant: {
    sid: string;
    identity: string;
    setMicrophoneEnabled: ReturnType<typeof vi.fn>;
  };
}

vi.mock('flavours/glitch/api', () => ({ default: () => api }));
vi.mock('flavours/glitch/store', () => ({ store: { dispatch } }));
vi.mock('livekit-client', () => {
  class Room {
    options: unknown;
    handlers = new Map<string, ((...args: unknown[]) => void)[]>();
    remoteParticipants = new Map();
    canPlaybackAudio = true;
    engine = { pcManager: undefined, rtcConfig: {} };
    connect = vi.fn(() => Promise.resolve());
    disconnect = vi.fn(() => Promise.resolve());
    switchActiveDevice = vi.fn(() => Promise.resolve(true));
    localParticipant = {
      sid: 'PA_local',
      identity: 'https://example.com/users/me',
      isScreenShareEnabled: false,
      setMicrophoneEnabled: vi.fn(() => Promise.resolve()),
      setScreenShareEnabled: vi.fn(() => Promise.resolve()),
      getTrackPublication: () => undefined,
    };

    constructor(options: unknown) {
      this.options = options;
      rooms.push(this);
    }

    on(event: string, handler: (...args: unknown[]) => void) {
      this.handlers.set(event, [...(this.handlers.get(event) ?? []), handler]);
      return this;
    }

    emit(event: string, ...args: unknown[]) {
      this.handlers.get(event)?.forEach((handler) => {
        handler(...args);
      });
    }

    getActiveDevice() {
      return 'default';
    }
  }
  const names = new Proxy({}, { get: (_target, key) => key });
  return {
    Room,
    RoomEvent: names,
    TrackEvent: names,
    DisconnectReason: {
      CLIENT_INITIATED: 1,
      DUPLICATE_IDENTITY: 2,
      PARTICIPANT_REMOVED: 4,
      ROOM_DELETED: 5,
    },
    Track: {
      Source: {
        Microphone: 'microphone',
        ScreenShare: 'screen_share',
        ScreenShareAudio: 'screen_share_audio',
      },
      Kind: { Audio: 'audio', Video: 'video' },
    },
  };
});

const credentials: VoiceCredentials = {
  url: 'wss://example.com/voice-signal',
  token: 'lk-token',
  identity: 'https://example.com/users/me',
  media_provider: 'https://voice.example.org',
  ice_servers: [
    { urls: ['turn:turn.example.org:3478'], username: 'u', credential: 'c' },
  ],
  screen_share_limits: null,
  allow_screen_share: true,
  max_participants: 10,
};

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('voice call engine', () => {
  beforeEach(() => {
    vi.resetModules();
    rooms.length = 0;
    api.post.mockReset().mockResolvedValue({ data: { accepted: true } });
    dispatch.mockReset();
    window.localStorage.clear();
  });

  it('connects with the relay ICE servers, opens the microphone and reports the status', async () => {
    const call = await import('../call');

    await call.connectVoiceCall({ id: '5', title: 'Room' }, credentials);
    await flush();

    const room = rooms[0];
    expect(room?.connect).toHaveBeenCalledWith(
      credentials.url,
      credentials.token,
      {
        autoSubscribe: false,
        rtcConfig: { iceServers: credentials.ice_servers },
      },
    );
    expect(call.voiceCallSnapshot()).toMatchObject({
      status: 'connected',
      conversation: { id: '5', title: 'Room' },
      micEnabled: true,
      allowScreenShare: true,
    });
    expect(api.post).toHaveBeenLastCalledWith(
      '/api/v1/chat/conversations/5/voice/status',
      { session_id: 'PA_local', mic_muted: false, deafened: false },
    );
  });

  it('turns the microphone off with the sound and remembers the choice', async () => {
    const call = await import('../call');
    await call.connectVoiceCall({ id: '5', title: 'Room' }, credentials, {
      micEnabled: false,
    });
    await flush();
    expect(call.voiceCallSnapshot().micEnabled).toBe(false);

    await call.setMicEnabled(true);
    call.setDeafened(true);
    await flush();

    expect(
      rooms[0]?.localParticipant.setMicrophoneEnabled,
    ).toHaveBeenLastCalledWith(false, expect.anything());
    expect(call.voiceCallSnapshot()).toMatchObject({
      micEnabled: false,
      deafened: true,
    });
    expect(api.post).toHaveBeenLastCalledWith(
      '/api/v1/chat/conversations/5/voice/status',
      { session_id: 'PA_local', mic_muted: true, deafened: true },
    );
    const preferences = await import('../preferences');
    expect(preferences.voicePreferences().micEnabled).toBe(true);
  });

  it('resets and explains when the server removes this participant', async () => {
    const call = await import('../call');
    await call.connectVoiceCall({ id: '5', title: 'Room' }, credentials);
    await flush();

    rooms[0]?.emit('Disconnected', 4);

    expect(call.voiceCallSnapshot().status).toBe('idle');
    const [action] = dispatch.mock.calls[0] as [
      { payload: { message: { id: string } } },
    ];
    expect(action.payload.message.id).toBe('chat.voice.ended.removed');
  });

  it('leaves without a notice and ignores a failed connection after leaving', async () => {
    const call = await import('../call');
    await call.connectVoiceCall({ id: '5', title: 'Room' }, credentials);
    await call.leaveVoiceCall();

    expect(rooms[0]?.disconnect).toHaveBeenCalled();
    expect(call.voiceCallSnapshot().status).toBe('idle');
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('stops retrying a status report the server refused', async () => {
    const call = await import('../call');
    api.post.mockRejectedValue(
      Object.assign(new Error('refused'), {
        isAxiosError: true,
        response: { status: 403, data: { error: 'Forbidden' } },
      }),
    );
    await call.connectVoiceCall({ id: '5', title: 'Room' }, credentials, {
      micEnabled: false,
    });
    await flush();
    await flush();

    expect(api.post).toHaveBeenCalledTimes(1);
  });
});
