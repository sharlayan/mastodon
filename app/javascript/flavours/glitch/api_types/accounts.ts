import type { ApiCustomEmojiJSON } from './custom_emoji';

export interface ApiAccountFieldJSON {
  name: string;
  value: string;
  verified_at: string | null;
}

export interface ApiAvatarDecorationJSON {
  id: string;
  name: string;
  url: string;
  static_url: string;
  category: string | null;
  angle: number;
  flip_h: boolean;
  offset_x: number;
  offset_y: number;
  scale: number;
  opacity: number;
}

export interface ApiAccountRoleJSON {
  color: string;
  id: string;
  name: string;
}

type ApiFeaturePolicy =
  | 'public'
  | 'followers'
  | 'following'
  | 'disabled'
  | 'unsupported_policy';

type ApiUserFeaturePolicy =
  | 'automatic'
  | 'manual'
  | 'denied'
  | 'missing'
  | 'unknown';

interface ApiFeaturePolicyJSON {
  automatic: ApiFeaturePolicy[];
  manual: ApiFeaturePolicy[];
  current_user: ApiUserFeaturePolicy;
}

// See app/serializers/rest/account_serializer.rb
export interface BaseApiAccountJSON {
  acct: string;
  avatar: string;
  avatar_static: string;
  avatar_description: string;
  bot: boolean;
  is_cat?: boolean;
  created_at: string;
  discoverable?: boolean;
  indexable: boolean;
  display_name: string;
  emojis: ApiCustomEmojiJSON[];
  feature_approval: ApiFeaturePolicyJSON;
  fields: ApiAccountFieldJSON[];
  followers_count: number;
  following_count: number;
  group: boolean;
  header: string;
  header_static: string;
  header_description: string;
  id: string;
  last_status_at: string | null;
  locked: boolean;
  show_media: boolean;
  show_media_replies: boolean;
  show_featured: boolean;
  noindex?: boolean;
  note: string;
  roles?: ApiAccountRoleJSON[];
  statuses_count: number;
  uri: string;
  url?: string;
  username: string;
  moved?: ApiAccountJSON;
  suspended?: boolean;
  limited?: boolean;
  memorial?: boolean;
  hide_collections: boolean;
  email_subscriptions?: boolean;
  followed_message?: string | null;
  avatar_decorations?: ApiAvatarDecorationJSON[];
  mfm?: boolean;
  server_features?: ApiServerFeaturesJSON;
  software?: string | null;
  online_status: ApiOnlineStatus;
  pages_view?: 'list' | 'blog';
  pages_blog_list_position?: 'left' | 'right';
  invalid_handle?: boolean;
}

export interface ApiServerFeaturesJSON {
  emoji_reaction: boolean;
  quote: boolean;
  status_reference: boolean;
  circle: boolean;
  avatar_decorations: boolean;
}

export type ApiOnlineStatus = 'unknown' | 'online' | 'active' | 'offline';

// See app/serializers/rest/muted_account_serializer.rb
export interface ApiMutedAccountJSON extends BaseApiAccountJSON {
  mute_expires_at?: string | null;
}

// For now, we have the same type representing both `Account` and `MutedAccount`
// objects, but we should refactor this in the future.
export type ApiAccountJSON = ApiMutedAccountJSON;

// See app/serializers/rest/streaming_reaction_user_serializer.rb
export type ApiStreamingReactionAccountJSON = Pick<
  BaseApiAccountJSON,
  | 'id'
  | 'username'
  | 'acct'
  | 'display_name'
  | 'avatar'
  | 'avatar_static'
  | 'emojis'
  | 'avatar_decorations'
> &
  Required<Pick<BaseApiAccountJSON, 'is_cat'>>;

// See app/serializers/rest/familiar_followers_serializer.rb
export type ApiFamiliarFollowersJSON = {
  id: string;
  accounts: ApiAccountJSON[];
}[];
