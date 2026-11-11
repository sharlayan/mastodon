import { emitChatStreamEvent, CHAT_STREAM_RECONNECTED } from '../../stream';
import type { VoiceState } from '../api';
import {
  applyVoiceState,
  resetVoiceStatesForTests,
  voiceStatesSnapshot,
  watchVoiceStates,
} from '../states';

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('flavours/glitch/api', () => ({ default: () => api }));

const state = (id: string, updatedAt: number, count = 1): VoiceState => ({
  conversation_id: id,
  available: true,
  active: count > 0,
  unavailable: false,
  max_participants: 10,
  updated_at: updatedAt,
  participants: Array.from({ length: count }, (_, index) => ({
    identity: `https://example.com/users/${index}`,
    account_id: String(index),
    account: {
      id: String(index),
      acct: `user${index}`,
      display_name: '',
      avatar: '',
      avatar_static: '',
    },
    screen_sharing: false,
    mic_muted: false,
    deafened: false,
  })),
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('voice call states', () => {
  beforeEach(() => {
    resetVoiceStatesForTests();
    api.get.mockReset();
  });

  it('keeps the newest state of each room, also from the stream', () => {
    expect(applyVoiceState(state('1', 20, 2))).toBe(true);
    expect(applyVoiceState(state('1', 10, 0))).toBe(false);
    expect(voiceStatesSnapshot().get('1')?.participants).toHaveLength(2);

    emitChatStreamEvent({
      event: 'chat.voice_state',
      payload: state('1', 30, 0),
    });
    expect(voiceStatesSnapshot().get('1')?.active).toBe(false);

    emitChatStreamEvent({ event: 'chat.voice_state', payload: { nope: true } });
    expect(voiceStatesSnapshot().size).toBe(1);
  });

  it('reads watched rooms in pages once and again after the stream comes back', async () => {
    const ids = Array.from({ length: 45 }, (_, index) => String(index));
    api.get.mockImplementation(
      (_url: string, { params }: { params: { conversation_ids: string[] } }) =>
        Promise.resolve({
          data: params.conversation_ids.map((id) => state(id, 1)),
        }),
    );

    const stop = watchVoiceStates(ids);
    const again = watchVoiceStates(['0']);
    await flush();

    expect(api.get).toHaveBeenCalledTimes(2);
    expect(
      (
        api.get.mock.calls[0] as [
          string,
          { params: { conversation_ids: string[] } },
        ]
      )[1].params.conversation_ids,
    ).toHaveLength(40);
    expect(voiceStatesSnapshot().size).toBe(45);

    emitChatStreamEvent({ event: CHAT_STREAM_RECONNECTED, payload: {} });
    await flush();
    expect(api.get).toHaveBeenCalledTimes(4);

    stop();
    again();
    emitChatStreamEvent({ event: CHAT_STREAM_RECONNECTED, payload: {} });
    await flush();
    expect(api.get).toHaveBeenCalledTimes(4);
  });

  it('reads a room again after a failed read', async () => {
    api.get.mockRejectedValueOnce(new Error('down'));
    const stop = watchVoiceStates(['7']);
    await flush();
    stop();

    api.get.mockResolvedValueOnce({ data: [state('7', 5)] });
    const restart = watchVoiceStates(['7']);
    await flush();
    expect(voiceStatesSnapshot().get('7')?.updated_at).toBe(5);
    restart();
  });
});
