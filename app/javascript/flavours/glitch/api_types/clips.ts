export interface ApiClipJSON {
  id: string;
  title: string;
  description: string | null;
  public: boolean;
  account_id: string;
  statuses_count: number;
  favourites_count: number;
  favourited?: boolean;
  created_at: string;
  updated_at: string;
}
