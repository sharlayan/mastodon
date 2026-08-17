import { readSharlayanInitialState } from './initial_state';
import type { SharlayanInitialStateMeta } from './initial_state';

const meta: SharlayanInitialStateMeta = {
  max_reactions: 3,
  force_local_only: true,
  federation_universe_enabled: true,
  circles_enabled: true,
  clips_enabled: true,
  pages_enabled: true,
  pages_drive_only: true,
  antenna_enabled: true,
  drive_enabled: true,
  board_announcements_enabled: true,
  avatar_decorations_enabled: true,
  avatar_decorations_federation_enabled: true,
  avatar_decorations_local_only_view: true,
  cat_enabled: true,
  cat_federation_enabled: true,
  color_scheme: 'dark',
  contrast: 'high',
  show_avatar_decorations: true,
  show_federated_avatar_decorations: true,
  show_cat: true,
  show_cat_speak: false,
  show_federated_cat: true,
  avatar_decoration_shape: 'square',
  force_round_avatar: false,
  local_account_statuses_access: 'authenticated',
  local_status_page_access: 'public',
  roleplay_mode: false,
  roleplay_disable_local_timeline: false,
  visible_reactions: 8,
  show_instance_info: true,
  custom_emoji_size: true,
  reaction_custom_emoji_size: true,
  reaction_local_emoji_only: true,
  reactions_enabled: true,
  mfm_enabled: true,
  mfm_animations: true,
  mfm_fold_mode: 'all',
  mfm_allow_composition: true,
  inline_compose_tabs: [{ type: 'list', id: '123' }],
  use_my_archive: false,
};

describe('Sharlayan initial state', () => {
  it('preserves enabled metadata and its exported defaults', () => {
    expect(readSharlayanInitialState({ meta, max_reactions: 5 })).toMatchObject(
      {
        maxReactions: 5,
        driveEnabled: true,
        federationUniverseEnabled: true,
        localTimelineEnabled: true,
        federatedTimelineEnabled: true,
        collectionsEnabled: true,
        pagesDriveOnly: true,
        antennaEnabled: true,
        showInstanceInfo: true,
        mfmFoldMode: 'all',
        avatarDecorationShape: 'square',
        forceRoundAvatar: false,
        avatarDecorationsLocalOnlyView: true,
        catEnabled: true,
        catFederationEnabled: true,
        showCat: true,
        showCatSpeak: false,
        showFederatedCat: true,
        customEmojiMutes: [],
        reactionMutes: [],
        inlineComposeTabs: [{ type: 'list', id: '123' }],
        userThemesEnabled: true,
        userThemeCatalog: '[]',
        userThemeDefaults: '{}',
        userTheme: '{}',
        useMyArchive: false,
      },
    );
  });

  it('keeps gate-off and guest defaults when state is absent', () => {
    expect(readSharlayanInitialState()).toMatchObject({
      maxReactions: 1,
      driveEnabled: false,
      pagesDriveOnly: false,
      antennaEnabled: false,
      localTimelineEnabled: true,
      federatedTimelineEnabled: true,
      collectionsEnabled: true,
      reactionsEnabled: true,
      mfmEnabled: true,
      mfmFoldMode: 'sensitive',
      avatarDecorationShape: 'round',
      forceRoundAvatar: false,
      avatarDecorationsLocalOnlyView: false,
      catEnabled: false,
      catFederationEnabled: false,
      showCat: true,
      showCatSpeak: true,
      showFederatedCat: true,
      inlineComposeTabs: [],
      userThemesEnabled: true,
      userThemeCatalog: '[]',
      userThemeDefaults: '{}',
      userTheme: '{}',
      useMyArchive: false,
    });
  });

  it('disables both timelines by default in roleplay mode', () => {
    expect(
      readSharlayanInitialState({
        meta: {
          ...meta,
          roleplay_mode: true,
          roleplay_disable_local_timeline: true,
          use_my_archive: undefined,
        },
      }),
    ).toMatchObject({
      roleplayMode: true,
      localTimelineEnabled: false,
      federatedTimelineEnabled: false,
      collectionsEnabled: false,
      catEnabled: false,
      catFederationEnabled: false,
      forceRoundAvatar: false,
      useMyArchive: true,
    });
  });

  it('allows only the local timeline when enabled in roleplay mode', () => {
    expect(
      readSharlayanInitialState({
        meta: {
          ...meta,
          roleplay_mode: true,
          roleplay_disable_local_timeline: false,
        },
      }),
    ).toMatchObject({
      localTimelineEnabled: true,
      federatedTimelineEnabled: false,
    });
  });

  it('preserves an explicit archive preference in roleplay mode', () => {
    expect(
      readSharlayanInitialState({
        meta: {
          ...meta,
          roleplay_mode: true,
          use_my_archive: false,
        },
      }),
    ).toMatchObject({
      roleplayMode: true,
      useMyArchive: false,
    });
  });
});
