// See app/serializers/rest/page_serializer.rb

import type { ApiAccountJSON } from './accounts';
import type { ApiMediaAttachmentJSON } from './media_attachments';

export interface ApiPageTextBlock {
  id: string;
  type: 'text';
  text: string;
  format?: 'mfm' | 'markdown';
  html?: string;
  spoiler?: boolean;
}

export interface ApiPageSectionBlock {
  id: string;
  type: 'section';
  title: string;
  children: ApiPageBlock[];
}

export interface ApiPageImageBlock {
  id: string;
  type: 'image';
  fileId: string | null;
  noUpscale?: boolean;
  spoiler?: boolean;
}

export interface ApiPageNoteBlock {
  id: string;
  type: 'note';
  note: string | null;
  detailed: boolean;
}

export interface ApiPageYoutubeBlock {
  id: string;
  type: 'youtube';
  url: string;
  size?: ApiPageYoutubeSize;
}

export type ApiPageBlock =
  | ApiPageTextBlock
  | ApiPageSectionBlock
  | ApiPageImageBlock
  | ApiPageNoteBlock
  | ApiPageYoutubeBlock;

export type ApiPageBlockType = ApiPageBlock['type'];
export type ApiPageYoutubeSize = 'small' | 'medium' | 'large';

export type ApiPageFont = 'sans-serif' | 'serif';
export type ApiPageVisibility =
  | 'public'
  | 'authenticated'
  | 'password'
  | 'private';

export interface ApiPageSeriesSummaryJSON {
  id: string;
  title: string;
  description: string | null;
  main_page_id: string | null;
  cover_media_attachment_id: string | null;
  cover_media_attachment: ApiMediaAttachmentJSON | null;
}

export interface ApiPageSeriesJSON extends ApiPageSeriesSummaryJSON {
  account_id: string;
  account: ApiAccountJSON;
  main_page_name: string | null;
  pages_count: number;
  created_at: string;
  updated_at: string;
}

export interface ApiPageJSON {
  id: string;
  title: string;
  name: string;
  summary: string | null;
  category: string | null;
  draft: boolean;
  visibility: ApiPageVisibility;
  locked: boolean;
  password?: string;
  content: ApiPageBlock[];
  align_center: boolean;
  hide_title_when_pinned: boolean;
  is_main: boolean;
  page_series_id: string | null;
  page_series: ApiPageSeriesSummaryJSON | null;
  series_position: number;
  series_main: boolean;
  font: ApiPageFont;
  account_id: string;
  account: ApiAccountJSON;
  eye_catching_media_attachment_id: string | null;
  eye_catching_media_attachment: ApiMediaAttachmentJSON | null;
  attached_media: ApiMediaAttachmentJSON[];
  likes_count: number;
  views_count: number;
  liked?: boolean;
  created_at: string;
  updated_at: string;
}

export interface ApiPageUnlockJSON {
  page: ApiPageJSON;
  access_token: string;
}
