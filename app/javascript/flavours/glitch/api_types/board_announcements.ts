// See app/serializers/rest/board_announcement_serializer.rb

import type { ApiCustomEmojiJSON } from './custom_emoji';

export interface ApiBoardAnnouncementAttachmentJSON {
  id: string;
  type: 'image' | 'file';
  url: string;
  preview_url: string;
  file_name: string;
  content_type: string;
  size: number;
  blurhash: string | null;
  meta: Record<string, unknown> | null;
}

export interface ApiBoardAnnouncementReactionJSON {
  name: string;
  count: number;
  me: boolean;
  url?: string;
  static_url?: string;
  is_sensitive?: boolean;
}

export type ApiBoardAnnouncementIcon = 'info' | 'warning' | 'error' | 'success';

export type ApiBoardAnnouncementDisplay = 'normal' | 'banner';

export interface ApiBoardAnnouncementJSON {
  id: string;
  title: string;
  content: string;
  icon: ApiBoardAnnouncementIcon;
  display: ApiBoardAnnouncementDisplay;
  need_confirmation_to_read: boolean;
  silence: boolean;
  published_at: string;
  updated_at: string;
  read: boolean;
  attachments: ApiBoardAnnouncementAttachmentJSON[];
  reactions: ApiBoardAnnouncementReactionJSON[];
  emojis: ApiCustomEmojiJSON[];
}

export interface ApiBoardAnnouncementUnreadCountJSON {
  count: number;
}
