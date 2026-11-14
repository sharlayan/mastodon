export interface ApiDriveFileJSON {
  id: string;
  type: 'image' | 'gifv' | 'video' | 'unknown' | 'audio';
  url: string;
  preview_url: string;
  meta: Record<string, unknown> | null;
  description: string | null;
  blurhash: string | null;
  sensitive: boolean;
  size: number | null;
  content_type: string | null;
  name: string | null;
  file_name: string | null;
  folder_id: string | null;
  orphaned: boolean;
  created_at: string;
}

export interface ApiDriveFolderJSON {
  id: string;
  name: string;
  parent_id: string | null;
  created_at: string;
  files_count?: number;
  folders_count?: number;
}

export interface ApiDriveUsageJSON {
  used: number;
  limit: number;
  file_count: number;
}

export interface ApiDriveSettingsJSON {
  keep_original_filename: boolean;
  default_folder_id: string | null;
  upload_original_image: boolean;
}
