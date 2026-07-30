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

export interface SharlayanInitialStateMeta {
  max_reactions: number;
  force_local_only: boolean;
  circles_enabled: boolean;
  clips_enabled: boolean;
  pages_enabled: boolean;
  antenna_enabled: boolean;
  drive_enabled: boolean;
  board_announcements_enabled: boolean;
  avatar_decorations_enabled: boolean;
  avatar_decorations_federation_enabled: boolean;
  cat_enabled: boolean;
  cat_federation_enabled: boolean;
  color_scheme?: 'auto' | 'light' | 'dark';
  contrast?: 'auto' | 'high';
  show_avatar_decorations?: boolean;
  show_federated_avatar_decorations?: boolean;
  show_cat?: boolean;
  show_federated_cat?: boolean;
  avatar_decoration_shape?: 'none' | 'round' | 'square';
  force_round_avatar?: boolean;
  local_account_statuses_access: 'public' | 'authenticated' | 'disabled';
  local_status_page_access: 'public' | 'authenticated' | 'disabled';
  roleplay_mode: boolean;
  admin_timeline_enabled?: boolean;
  admin_timeline_owner_viewer?: boolean;
  soft_hide_deletion?: boolean;
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

  return {
    colorScheme: getMeta('color_scheme') ?? 'auto',
    contrast: getMeta('contrast') ?? 'auto',
    maxReactions: initialState?.max_reactions ?? 1,
    localAccountStatusesAccess: getMeta('local_account_statuses_access'),
    localStatusPageAccess: getMeta('local_status_page_access'),
    forceLocalOnly: getMeta('force_local_only') === true,
    roleplayMode: getMeta('roleplay_mode') === true,
    collectionsEnabled: getMeta('roleplay_mode') !== true,
    circlesEnabled: getMeta('circles_enabled') === true,
    clipsEnabled: getMeta('clips_enabled') === true,
    pagesEnabled: getMeta('pages_enabled') === true,
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
    showAvatarDecorations: getMeta('show_avatar_decorations') ?? false,
    showFederatedAvatarDecorations:
      getMeta('show_federated_avatar_decorations') ?? false,
    catEnabled: getMeta('cat_enabled') === true,
    catFederationEnabled: getMeta('cat_federation_enabled') === true,
    showCat: getMeta('show_cat') ?? true,
    showFederatedCat: getMeta('show_federated_cat') ?? true,
    avatarDecorationShape:
      getMeta('avatar_decoration_shape') ?? (isSignedIn ? 'none' : 'round'),
    forceRoundAvatar: getMeta('force_round_avatar') ?? false,
    adminTimelineEnabled: getMeta('admin_timeline_enabled') === true,
    adminTimelineOwnerViewer: getMeta('admin_timeline_owner_viewer'),
    softHideDeletion: getMeta('soft_hide_deletion') === true,
  };
};
