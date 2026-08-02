const preferences = {
  catEnabled: true,
  catFederationEnabled: true,
  me: '1',
  showCat: true,
  showCatSpeak: true,
  showFederatedCat: true,
};

export {};

vi.mock('flavours/glitch/initial_state', () => ({
  get catEnabled() {
    return preferences.catEnabled;
  },
  get catFederationEnabled() {
    return preferences.catFederationEnabled;
  },
  get me() {
    return preferences.me;
  },
  get showCat() {
    return preferences.showCat;
  },
  get showCatSpeak() {
    return preferences.showCatSpeak;
  },
  get showFederatedCat() {
    return preferences.showFederatedCat;
  },
}));

const { catEffectsVisibleFor, catSpeakVisibleFor } = await import('./nyaify');

beforeEach(() => {
  preferences.catEnabled = true;
  preferences.catFederationEnabled = true;
  preferences.me = '1';
  preferences.showCat = true;
  preferences.showCatSpeak = true;
  preferences.showFederatedCat = true;
});

describe('cat effect visibility', () => {
  it('can hide cat speak without hiding other cat effects', () => {
    preferences.showCatSpeak = false;

    expect(catEffectsVisibleFor('cat', true)).toBe(true);
    expect(catSpeakVisibleFor('cat', true)).toBe(false);
  });

  it('keeps cat speak behind the shared cat-effect preference', () => {
    preferences.showCat = false;

    expect(catEffectsVisibleFor('cat', true)).toBe(false);
    expect(catSpeakVisibleFor('cat', true)).toBe(false);
  });
});
