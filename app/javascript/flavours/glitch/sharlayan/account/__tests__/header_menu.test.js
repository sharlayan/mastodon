const gate = {
  avatarDecorationsEnabled: true,
  showAvatarDecorations: true,
};

vi.mock('flavours/glitch/initial_state', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    get avatarDecorationsEnabled() {
      return gate.avatarDecorationsEnabled;
    },
    get showAvatarDecorations() {
      return gate.showAvatarDecorations;
    },
  };
});

let headerMenu;

const intl = { formatMessage: (msg) => msg.id };

const context = (overrides = {}) => ({
  account: {
    id: '1',
    acct: 'bob@remote.example',
    username: 'bob',
    avatar_decorations: [{ id: 'd1' }],
  },
  relationship: {},
  dispatch: vi.fn(),
  intl,
  signedIn: true,
  isRemote: true,
  remoteDomain: 'remote.example',
  ...overrides,
});

const texts = (items) => items.filter(Boolean).map((item) => item.text);

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  headerMenu = await import('../header_menu');
});

beforeEach(() => {
  gate.avatarDecorationsEnabled = true;
  gate.showAvatarDecorations = true;
});

describe('sharlayanRefetchProfileItems', () => {
  it('offers a refresh only for signed-in remote accounts', () => {
    expect(texts(headerMenu.sharlayanRefetchProfileItems(context()))).toEqual([
      'account.menu.refetch_profile',
    ]);
    expect(
      headerMenu.sharlayanRefetchProfileItems(
        context({ isRemote: false, remoteDomain: null }),
      ),
    ).toEqual([]);
    expect(
      headerMenu.sharlayanRefetchProfileItems(context({ signedIn: false })),
    ).toEqual([]);
  });
});

describe('sharlayanReactionMuteItems', () => {
  it('includes decoration and domain reaction mutes when applicable', () => {
    expect(texts(headerMenu.sharlayanReactionMuteItems(context()))).toEqual([
      'account.menu.mute_decorations',
      'account.menu.mute_reactions',
      'account.menu.mute_domain_reactions',
    ]);
  });

  it('drops the decoration mute when the feature is disabled', () => {
    gate.avatarDecorationsEnabled = false;
    expect(texts(headerMenu.sharlayanReactionMuteItems(context()))).toEqual([
      'account.menu.mute_reactions',
      'account.menu.mute_domain_reactions',
    ]);
  });

  it('drops the domain reaction mute for local accounts', () => {
    expect(
      texts(
        headerMenu.sharlayanReactionMuteItems(
          context({ remoteDomain: null, isRemote: false }),
        ),
      ),
    ).toEqual(['account.menu.mute_decorations', 'account.menu.mute_reactions']);
  });
});

describe('sharlayan admin decoration items', () => {
  it('gates admin block items on the decoration feature', () => {
    expect(
      texts(headerMenu.sharlayanAdminAccountDecorationItems(context())),
    ).toEqual(['account.menu.admin_block_decorations']);
    expect(
      texts(headerMenu.sharlayanAdminDomainDecorationItems(context())),
    ).toEqual(['account.menu.admin_block_domain_decorations']);

    gate.avatarDecorationsEnabled = false;
    expect(
      headerMenu.sharlayanAdminAccountDecorationItems(context()),
    ).toEqual([]);
    expect(
      headerMenu.sharlayanAdminDomainDecorationItems(context()),
    ).toEqual([]);
  });
});
