import type { ApiAnnualReportState } from './api/annual_report';
import type { ApiAccountJSON } from './api_types/accounts';

type InitialStateLanguage = [code: string, name: string, localName: string];

interface InitialStateMeta {
  access_token: string;
  advanced_layout?: boolean;
  auto_play_gif: boolean;
  activity_api_enabled: boolean;
  admin: string;
  boost_modal?: boolean;
  quick_boosting?: boolean;
  favourite_modal?: boolean;
  crop_images: boolean;
  delete_modal?: boolean;
  missing_alt_text_modal?: boolean;
  disable_swiping?: boolean;
  disable_hover_cards?: boolean;
  disabled_account_id?: string;
  display_media: string;
  domain: string;
  expand_spoilers?: boolean;
  limited_federation_mode: boolean;
  locale: string;
  mascot: string | null;
  max_reactions: number;
  me?: string;
  moved_to_account_id?: string;
  owner?: string;
  profile_directory: boolean;
  registrations_open: boolean;
  reduce_motion: boolean;
  repository: string;
  search_enabled: boolean;
  trends_enabled: boolean;
  single_user_mode: boolean;
  source_url: string;
  streaming_api_base_url: string;
  force_local_only: boolean;
  circles_enabled: boolean;
  clips_enabled: boolean;
  antenna_enabled: boolean;
  board_announcements_enabled: boolean;
  avatar_decorations_enabled: boolean;
  avatar_decorations_federation_enabled: boolean;
  color_scheme?: 'auto' | 'light' | 'dark';
  contrast?: 'auto' | 'high';
  show_avatar_decorations?: boolean;
  show_federated_avatar_decorations?: boolean;
  force_round_avatar_decoration?: boolean;
  force_round_avatar?: boolean;
  local_account_statuses_access: 'public' | 'authenticated' | 'disabled';
  local_status_page_access: 'public' | 'authenticated' | 'disabled';
  local_live_feed_access: 'public' | 'authenticated' | 'disabled';
  remote_live_feed_access: 'public' | 'authenticated' | 'disabled';
  local_topic_feed_access: 'public' | 'authenticated';
  remote_topic_feed_access: 'public' | 'authenticated' | 'disabled';
  title: string;
  show_trends: boolean;
  landing_page: 'about' | 'trends' | 'local_feed';
  use_blurhash: boolean;
  use_pending_items?: boolean;
  version: string;
  visible_reactions: number;
  sso_redirect: string;
  status_page_url: string;
  terms_of_service_enabled: boolean;
  emoji_style?: string;
  wrapstodon?: InitialStateWrapstodon | null;
  default_content_type: string;
  show_instance_info: boolean;
  custom_emoji_size: boolean;
  reaction_custom_emoji_size: boolean;
  reaction_local_emoji_only: boolean;
  reactions_enabled: boolean;
  mfm_enabled: boolean;
  mfm_animations: boolean;
  mfm_fold_mode: 'show' | 'sensitive' | 'all';
  mfm_allow_composition: boolean;
  roleplay_mode?: boolean;
  custom_emoji_mute_hidden?: boolean;
  custom_emoji_mutes?: ApiCustomEmojiMuteJSON[];
  reaction_mutes?: ApiReactionMuteJSON[];
}

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

interface IntialStateRole {
  id: string;
  name: string;
  permissions: string;
  extra_permissions: string;
  color: string;
  highlighted: boolean;
  collection_limit: number;
}

interface PollLimits {
  max_options: number;
  max_option_chars: number;
  min_expiration: number;
  max_expiration: number;
}

interface InitialStateWrapstodon {
  year: number;
  state: ApiAnnualReportState;
}

interface InitialStateCompose {
  text: string;
  default_privacy?: string;
  default_sensitive?: boolean;
  default_language?: string;
  default_quote_policy?: string;
  me?: string;
}

export interface InitialState {
  accounts: Record<string, ApiAccountJSON>;
  languages: InitialStateLanguage[];
  compose: InitialStateCompose;
  critical_updates_pending?: boolean;
  meta: InitialStateMeta;
  role?: IntialStateRole;
  features: string[];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  local_settings: any;
  max_feed_hashtags: number;
  poll_limits: PollLimits;
  max_reactions: number;
}

const element = document.getElementById('initial-state');
export const initialState: InitialState | undefined = element?.textContent
  ? (JSON.parse(element.textContent) as InitialState)
  : undefined;

const initialPath: string =
  document
    .querySelector('head meta[name=initialPath]')
    ?.getAttribute('content') ?? '';
export const hasMultiColumnPath: boolean =
  initialPath === '/' ||
  initialPath === '/getting-started' ||
  initialPath === '/home' ||
  initialPath.startsWith('/deck');

// Glitch-soc-specific “local settings”
if (initialState) {
  try {
    const initialStateString = localStorage.getItem('mastodon-settings');
    if (initialStateString) {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      initialState.local_settings = JSON.parse(initialStateString);
    }
  } catch {
    initialState.local_settings = {};
  }
}

function getMeta<K extends keyof InitialStateMeta>(
  prop: K,
): InitialStateMeta[K] | undefined {
  return initialState?.meta[prop];
}

export const activityApiEnabled = getMeta('activity_api_enabled');
export const autoPlayGif = getMeta('auto_play_gif');
export const boostModal = getMeta('boost_modal');
export const colorScheme = getMeta('color_scheme') ?? 'auto';
export const contrast = getMeta('contrast') ?? 'auto';
export const quickBoosting = getMeta('quick_boosting');
export const deleteModal = getMeta('delete_modal');
export const missingAltTextModal = getMeta('missing_alt_text_modal');
export const disableSwiping = getMeta('disable_swiping');
export const disableHoverCards = getMeta('disable_hover_cards');
export const disabledAccountId = getMeta('disabled_account_id');
export const displayMedia = getMeta('display_media');
export const domain = getMeta('domain');
export const emojiStyle = getMeta('emoji_style') ?? 'auto';
export const expandSpoilers = getMeta('expand_spoilers');
export const forceSingleColumn = !getMeta('advanced_layout');
export const limitedFederationMode = getMeta('limited_federation_mode');
export const mascot = getMeta('mascot');
export const maxReactions = initialState?.max_reactions ?? 1;
export const me = getMeta('me');
export const movedToAccountId = getMeta('moved_to_account_id');
export const owner = getMeta('owner');
export const profile_directory = getMeta('profile_directory');
export const reduceMotion = getMeta('reduce_motion');
export const registrationsOpen = getMeta('registrations_open');
export const repository = getMeta('repository');
export const searchEnabled = getMeta('search_enabled');
export const trendsEnabled = getMeta('trends_enabled');
export const showTrends = getMeta('show_trends');
export const singleUserMode = getMeta('single_user_mode');
export const source_url = getMeta('source_url');
export const localAccountStatusesAccess = getMeta(
  'local_account_statuses_access',
);
export const localStatusPageAccess = getMeta('local_status_page_access');
export const forceLocalOnly = getMeta('force_local_only');
export const circlesEnabled = getMeta('circles_enabled') === true;
export const clipsEnabled = getMeta('clips_enabled') === true;
export const collectionsEnabled = false as boolean;
export const antennaEnabled = getMeta('antenna_enabled') === true;
export const boardAnnouncementsEnabled =
  getMeta('board_announcements_enabled') === true;
export const localLiveFeedAccess = getMeta('local_live_feed_access');
export const remoteLiveFeedAccess = getMeta('remote_live_feed_access');
export const localTopicFeedAccess = getMeta('local_topic_feed_access');
export const remoteTopicFeedAccess = getMeta('remote_topic_feed_access');
export const title = getMeta('title');
export const landingPage = getMeta('landing_page');
export const useBlurhash = getMeta('use_blurhash');
export const usePendingItems = getMeta('use_pending_items');
export const version = getMeta('version');
export const visibleReactions = getMeta('visible_reactions');
export const criticalUpdatesPending = initialState?.critical_updates_pending;
export const statusPageUrl = getMeta('status_page_url');
export const sso_redirect = getMeta('sso_redirect');
export const termsOfServiceEnabled = getMeta('terms_of_service_enabled');
export const showInstanceInfo = getMeta('show_instance_info');
export const customEmojiSize = getMeta('custom_emoji_size');
export const customEmojiMutes = getMeta('custom_emoji_mutes') ?? [];
export const customEmojiMuteHidden =
  getMeta('custom_emoji_mute_hidden') === true;
export const reactionMutes = getMeta('reaction_mutes') ?? [];
export const reactionCustomEmojiSize = getMeta('reaction_custom_emoji_size');
export const reactionLocalEmojiOnly = getMeta('reaction_local_emoji_only');
export const reactionsEnabled = getMeta('reactions_enabled') !== false;
export const mfmEnabled = getMeta('mfm_enabled') !== false;
export const mfmAllowComposition = getMeta('mfm_allow_composition') === true;
export const mfmAnimations = getMeta('mfm_animations') !== false;
export const mfmFoldMode =
  (getMeta('mfm_fold_mode') as string | undefined) ?? 'sensitive';
export const wrapstodon = getMeta('wrapstodon');
export const roleplayMode = getMeta('roleplay_mode');
export const avatarDecorationsEnabled = getMeta('avatar_decorations_enabled');
export const avatarDecorationsFederationEnabled = getMeta(
  'avatar_decorations_federation_enabled',
);
export const showAvatarDecorations =
  getMeta('show_avatar_decorations') ?? false;
export const showFederatedAvatarDecorations =
  getMeta('show_federated_avatar_decorations') ?? false;
export const forceRoundAvatarDecoration =
  getMeta('force_round_avatar_decoration') ?? !me;
export const forceRoundAvatar = getMeta('force_round_avatar') ?? false;

const displayNames =
  // Intl.DisplayNames can be undefined in old browsers
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
  Intl.DisplayNames &&
  (new Intl.DisplayNames(getMeta('locale'), {
    type: 'language',
    fallback: 'none',
    languageDisplay: 'standard',
  }) as Intl.DisplayNames | undefined);

export const languages = initialState?.languages.map((lang) => {
  // zh-YUE is not a valid CLDR unicode_language_id
  return [
    lang[0],
    displayNames?.of(lang[0].replace('zh-YUE', 'yue')) ?? lang[1],
    lang[2],
  ] as InitialStateLanguage;
});

// Glitch-soc-specific settings
export const maxFeedHashtags = initialState?.max_feed_hashtags ?? 4;
export const favouriteModal = getMeta('favourite_modal');
export const pollLimits = initialState?.poll_limits;
export const defaultContentType = getMeta('default_content_type');

export function getAccessToken(): string | undefined {
  return getMeta('access_token');
}
