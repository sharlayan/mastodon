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

const api = vi.hoisted(() => ({
  post: vi.fn(),
  mute: vi.fn(),
}));

vi.mock('flavours/glitch/api', async (importOriginal) => ({
  ...(await importOriginal()),
  apiRequestPost: api.post,
}));

vi.mock('flavours/glitch/actions/reaction_mutes', () => ({
  createReactionMute: (params) => ({ type: 'reaction_mutes/create', params }),
}));

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

  it('drops the domain reaction mute for accounts with invalid handles', () => {
    expect(
      texts(
        headerMenu.sharlayanReactionMuteItems(
          context({
            account: {
              ...context().account,
              invalid_handle: true,
            },
            remoteDomain: 'handle.invalid',
          }),
        ),
      ),
    ).toEqual(['account.menu.mute_decorations', 'account.menu.mute_reactions']);
  });
});

describe('sharlayanReactionMuteItems actions', () => {
  const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

  const run = async (index, outcome) => {
    const dispatch = vi.fn((action) =>
      action.type === 'reaction_mutes/create'
        ? Promise.resolve({ ...action, meta: { requestId: '1', requestStatus: outcome } })
        : action,
    );
    const items = headerMenu.sharlayanReactionMuteItems(context({ dispatch })).filter(Boolean);
    items[index].action();
    await settle();
    return dispatch.mock.calls.map(([action]) => action);
  };

  it('mutes reactions through the store and confirms success', async () => {
    const accountActions = await run(1, 'fulfilled');
    expect(accountActions[0]).toEqual({ type: 'reaction_mutes/create', params: { account_id: '1' } });
    expect(accountActions[1].payload.message.id).toBe('account.menu.mute_reactions_done');

    const domainActions = await run(2, 'fulfilled');
    expect(domainActions[0]).toEqual({ type: 'reaction_mutes/create', params: { domain: 'remote.example' } });
    expect(domainActions[1].payload.message.id).toBe('account.menu.mute_domain_reactions_done');
  });

  it('leaves failed reaction mutes to the rejected action alert', async () => {
    expect(await run(1, 'rejected')).toHaveLength(1);
  });

  it('reports decoration mute success and failure', async () => {
    api.post.mockResolvedValueOnce({});
    const success = await run(0, 'fulfilled');
    expect(api.post).toHaveBeenCalledWith('v1/avatar_decoration_mutes', { account_id: '1' });
    expect(success[0].payload.message.id).toBe('account.menu.mute_decorations_done');

    api.post.mockRejectedValueOnce(new Error('boom'));
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const failure = await run(0, 'fulfilled');
    expect(failure[0].type).toBe('alerts/show');
    expect(failure[0].payload.message.id).not.toBe('account.menu.mute_decorations_done');
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
