import { DEFAULT_PREFERENCES, parsePreferences } from '../preferences';

describe('voice call preferences', () => {
  it('falls back to defaults for missing or broken values', () => {
    expect(parsePreferences(null)).toEqual(DEFAULT_PREFERENCES);
    expect(parsePreferences('not json')).toEqual(DEFAULT_PREFERENCES);
    expect(parsePreferences('[]')).toEqual(DEFAULT_PREFERENCES);
  });

  it('keeps valid values and drops invalid ones', () => {
    const parsed = parsePreferences(
      JSON.stringify({
        inputDeviceId: 'mic-1',
        outputDeviceId: 3,
        echoCancellation: false,
        micEnabled: 'yes',
        screenShareQuality: 'ultra',
        voiceVolumes: { a: 2, b: -1, c: 0.5, d: 'loud' },
        acknowledgedMediaProviders: ['https://voice.example.org', 1],
      }),
    );

    expect(parsed).toMatchObject({
      inputDeviceId: 'mic-1',
      outputDeviceId: null,
      echoCancellation: false,
      micEnabled: true,
      screenShareQuality: 'sharp',
      voiceVolumes: { a: 1, b: 0, c: 0.5 },
      acknowledgedMediaProviders: ['https://voice.example.org'],
    });
  });
});
