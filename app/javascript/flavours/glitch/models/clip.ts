import type { RecordOf } from 'immutable';
import { Record } from 'immutable';

import type { ApiClipJSON } from 'flavours/glitch/api_types/clips';

interface ClipShape {
  id: string;
  title: string;
  description: string | null;
  public: boolean;
  statuses_count: number;
  account_id: string;
}

export type Clip = RecordOf<ClipShape>;

const ClipFactory = Record<ClipShape>({
  id: '',
  title: '',
  description: null,
  public: false,
  statuses_count: 0,
  account_id: '',
});

export function createClip(clip: ApiClipJSON): Clip {
  return ClipFactory({
    id: clip.id,
    title: clip.title,
    description: clip.description,
    public: clip.public,
    statuses_count: clip.statuses_count,
    account_id: clip.account_id,
  });
}
