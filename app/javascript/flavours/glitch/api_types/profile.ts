import type { ApiAccountFieldJSON } from './accounts';
import type { ApiFeaturedTagJSON } from './tags';

export interface ApiProfileDecorationConfigJSON {
  id: string;
  angle: number;
  flip_h: boolean;
  offset_x: number;
  offset_y: number;
  scale: number;
  opacity: number;
}

export interface ApiProfileJSON {
  id: string;
  display_name: string;
  note: string;
  fields: ApiAccountFieldJSON[];
  avatar: string;
  avatar_static: string;
  avatar_description: string;
  header: string;
  header_static: string;
  header_description: string;
  locked: boolean;
  bot: boolean;
  hide_collections: boolean;
  discoverable: boolean;
  indexable: boolean;
  show_media: boolean;
  show_media_replies: boolean;
  show_featured: boolean;
  attribution_domains: string[];
  featured_tags: ApiFeaturedTagJSON[];
  followed_message: string | null;
  is_cat: boolean;
  avatar_decorations: ApiProfileDecorationConfigJSON[];
}

export type ApiProfileUpdateParams = Partial<
  Pick<
    ApiProfileJSON,
    | 'avatar_description'
    | 'header_description'
    | 'display_name'
    | 'note'
    | 'locked'
    | 'bot'
    | 'hide_collections'
    | 'discoverable'
    | 'indexable'
    | 'show_media'
    | 'show_media_replies'
    | 'show_featured'
    | 'followed_message'
    | 'is_cat'
  >
> & {
  attribution_domains?: string[];
  fields_attributes?: Pick<ApiAccountFieldJSON, 'name' | 'value'>[];
  avatar_decorations?: ApiProfileDecorationConfigJSON[];
};
