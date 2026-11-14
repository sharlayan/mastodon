// See app/serializers/rest/custom_emoji_serializer.rb
export interface ApiCustomEmojiJSON {
  shortcode: string;
  static_url: string;
  url: string;
  category?: string;
  featured?: boolean;
  visible_in_picker: boolean;
  is_sensitive?: boolean;
  local_only?: boolean;
  aliases?: string[];
  license?: string;
  domain?: string;
}
