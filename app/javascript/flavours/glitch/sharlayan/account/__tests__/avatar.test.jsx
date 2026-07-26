const gate = {
  avatarDecorationsEnabled: true,
  me: '1',
  showAvatarDecorations: true,
  showFederatedAvatarDecorations: true,
  avatarDecorationShape: 'circle',
};

vi.mock('flavours/glitch/initial_state', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    get avatarDecorationsEnabled() {
      return gate.avatarDecorationsEnabled;
    },
    get me() {
      return gate.me;
    },
    get showAvatarDecorations() {
      return gate.showAvatarDecorations;
    },
    get showFederatedAvatarDecorations() {
      return gate.showFederatedAvatarDecorations;
    },
    get avatarDecorationShape() {
      return gate.avatarDecorationShape;
    },
  };
});

let sharlayanHasAvatarDecorations;

const account = (overrides = {}) => ({
  acct: 'alice',
  avatar_decorations: [{ id: '1', url: 'x', static_url: 'x' }],
  ...overrides,
});

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ sharlayanHasAvatarDecorations } = await import('../avatar'));
}, 30_000);

beforeEach(() => {
  gate.avatarDecorationsEnabled = true;
  gate.me = '1';
  gate.showAvatarDecorations = true;
  gate.showFederatedAvatarDecorations = true;
});

describe('sharlayanHasAvatarDecorations', () => {
  it('shows decorations for a local account when the feature and preference are on', () => {
    expect(sharlayanHasAvatarDecorations(account())).toBe(true);
  });

  it('is false when the feature gate is disabled', () => {
    gate.avatarDecorationsEnabled = false;
    expect(sharlayanHasAvatarDecorations(account())).toBe(false);
  });

  it('is false with no decorations', () => {
    expect(sharlayanHasAvatarDecorations(account({ avatar_decorations: [] }))).toBe(
      false,
    );
  });

  it('hides remote decorations unless federated decorations are enabled', () => {
    const remote = account({ acct: 'bob@remote.example' });
    gate.showFederatedAvatarDecorations = false;
    expect(sharlayanHasAvatarDecorations(remote)).toBe(false);
    gate.showFederatedAvatarDecorations = true;
    expect(sharlayanHasAvatarDecorations(remote)).toBe(true);
  });

  it('shows decorations to guests and via forceShow even when the preference is off', () => {
    gate.showAvatarDecorations = false;
    expect(sharlayanHasAvatarDecorations(account())).toBe(false);
    expect(sharlayanHasAvatarDecorations(account(), true)).toBe(true);

    gate.me = null;
    expect(sharlayanHasAvatarDecorations(account())).toBe(true);
  });
});
