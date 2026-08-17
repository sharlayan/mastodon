export interface ApiCustomEmojiMuteJSON {
  id: string;
  prefix: string;
  domain: string;
  reject_reactions: boolean;
  hide_in_picker: boolean;
}

export interface ApiReactionMuteJSON {
  id: string;
  target_account_id: string | null;
  target_acct: string | null;
  target_domain: string | null;
}

export interface InlineComposeTab {
  type: 'list' | 'antenna';
  id: string;
}

export interface SharlayanInitialStateMeta {
  max_reactions: number;
  force_local_only: boolean;
  federation_universe_enabled?: boolean;
  circles_enabled: boolean;
  clips_enabled: boolean;
  pages_enabled: boolean;
  pages_drive_only: boolean;
  antenna_enabled: boolean;
  drive_enabled: boolean;
  board_announcements_enabled: boolean;
  avatar_decorations_enabled: boolean;
  avatar_decorations_federation_enabled: boolean;
  avatar_decorations_local_only_view: boolean;
  cat_enabled: boolean;
  cat_federation_enabled: boolean;
  color_scheme?: 'auto' | 'light' | 'dark';
  contrast?: 'auto' | 'high';
  show_avatar_decorations?: boolean;
  show_federated_avatar_decorations?: boolean;
  show_cat?: boolean;
  show_cat_speak?: boolean;
  show_federated_cat?: boolean;
  avatar_decoration_shape?: 'none' | 'round' | 'square';
  force_round_avatar?: boolean;
  local_account_statuses_access: 'public' | 'authenticated' | 'disabled';
  local_status_page_access: 'public' | 'authenticated' | 'disabled';
  roleplay_mode: boolean;
  roleplay_disable_local_timeline: boolean;
  roleplay_hide_public_timelines_from_admins: boolean;
  admin_timeline_owner_viewer?: boolean;
  soft_hide_deletion?: boolean;
  user_themes_enabled?: boolean;
  server_stored_account_switching_enabled: boolean;
  user_theme_catalog?: string;
  user_theme_defaults?: string;
  user_theme?: string;
  use_my_archive?: boolean;
  visible_reactions: number;
  show_instance_info: boolean;
  custom_emoji_size: boolean;
  reaction_custom_emoji_size: boolean;
  reaction_local_emoji_only: boolean;
  reactions_enabled: boolean;
  mfm_enabled: boolean;
  mfm_animations: boolean;
  mfm_fold_mode: 'show' | 'sensitive' | 'all';
  mfm_allow_composition: boolean;
  custom_emoji_mute_hidden?: boolean;
  ignore_others_pages_view?: boolean;
  custom_emoji_mutes?: ApiCustomEmojiMuteJSON[];
  reaction_mutes?: ApiReactionMuteJSON[];
  inline_compose_tabs?: InlineComposeTab[];
}

export interface SharlayanInitialState {
  max_reactions: number;
}

export const readSharlayanInitialState = (
  initialState?: {
    meta: SharlayanInitialStateMeta;
  } & Partial<SharlayanInitialState>,
  isSignedIn = false,
) => {
  const getMeta = <K extends keyof SharlayanInitialStateMeta>(key: K) =>
    initialState?.meta[key];
  const roleplayMode = getMeta('roleplay_mode') === true;

  return {
    colorScheme: getMeta('color_scheme') ?? 'auto',
    contrast: getMeta('contrast') ?? 'auto',
    maxReactions: initialState?.max_reactions ?? 1,
    localAccountStatusesAccess: getMeta('local_account_statuses_access'),
    localStatusPageAccess: getMeta('local_status_page_access'),
    forceLocalOnly: getMeta('force_local_only') === true,
    federationUniverseEnabled: getMeta('federation_universe_enabled') === true,
    roleplayMode,
    collectionsEnabled: !roleplayMode,
    circlesEnabled: getMeta('circles_enabled') === true,
    clipsEnabled: getMeta('clips_enabled') === true,
    pagesEnabled: getMeta('pages_enabled') === true,
    pagesDriveOnly: getMeta('pages_drive_only') === true,
    antennaEnabled: getMeta('antenna_enabled') === true,
    driveEnabled: getMeta('drive_enabled') === true,
    boardAnnouncementsEnabled: getMeta('board_announcements_enabled') === true,
    visibleReactions: getMeta('visible_reactions'),
    showInstanceInfo: getMeta('show_instance_info'),
    customEmojiSize: getMeta('custom_emoji_size'),
    customEmojiMutes: getMeta('custom_emoji_mutes') ?? [],
    customEmojiMuteHidden: getMeta('custom_emoji_mute_hidden') === true,
    ignoreOthersPagesView: getMeta('ignore_others_pages_view') === true,
    reactionMutes: getMeta('reaction_mutes') ?? [],
    inlineComposeTabs: getMeta('inline_compose_tabs') ?? [],
    reactionCustomEmojiSize: getMeta('reaction_custom_emoji_size'),
    reactionLocalEmojiOnly: getMeta('reaction_local_emoji_only'),
    reactionsEnabled: getMeta('reactions_enabled') !== false,
    mfmEnabled: getMeta('mfm_enabled') !== false,
    mfmAllowComposition: getMeta('mfm_allow_composition') === true,
    mfmAnimations: getMeta('mfm_animations') !== false,
    mfmFoldMode: getMeta('mfm_fold_mode') ?? 'sensitive',
    avatarDecorationsEnabled: getMeta('avatar_decorations_enabled'),
    avatarDecorationsFederationEnabled: getMeta(
      'avatar_decorations_federation_enabled',
    ),
    avatarDecorationsLocalOnlyView:
      getMeta('avatar_decorations_local_only_view') === true,
    showAvatarDecorations: getMeta('show_avatar_decorations') ?? false,
    showFederatedAvatarDecorations:
      getMeta('show_federated_avatar_decorations') ?? false,
    catEnabled: !roleplayMode && getMeta('cat_enabled') === true,
    catFederationEnabled:
      !roleplayMode && getMeta('cat_federation_enabled') === true,
    showCat: getMeta('show_cat') ?? true,
    showCatSpeak: getMeta('show_cat_speak') ?? true,
    showFederatedCat: getMeta('show_federated_cat') ?? true,
    avatarDecorationShape:
      getMeta('avatar_decoration_shape') ?? (isSignedIn ? 'none' : 'round'),
    forceRoundAvatar: getMeta('force_round_avatar') === true,
    adminTimelineOwnerViewer: getMeta('admin_timeline_owner_viewer') === true,
    softHideDeletion: getMeta('soft_hide_deletion') === true,
    userThemesEnabled: getMeta('user_themes_enabled') !== false,
    serverStoredAccountSwitchingEnabled:
      getMeta('server_stored_account_switching_enabled') !== false,
    userThemeCatalog: getMeta('user_theme_catalog') ?? '[]',
    userThemeDefaults: getMeta('user_theme_defaults') ?? '{}',
    userTheme: getMeta('user_theme') ?? '{}',
    useMyArchive: getMeta('use_my_archive') ?? roleplayMode,
  };
};
