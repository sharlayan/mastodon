// See app/serializers/rest/board_announcement_serializer.rb

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
}

export interface ApiBoardAnnouncementJSON {
  id: string;
  title: string;
  content: string;
  published_at: string;
  updated_at: string;
  read: boolean;
  attachments: ApiBoardAnnouncementAttachmentJSON[];
  reactions: ApiBoardAnnouncementReactionJSON[];
}

export interface ApiBoardAnnouncementUnreadCountJSON {
  count: number;
}
