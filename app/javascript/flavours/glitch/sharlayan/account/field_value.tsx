import type { cleanExtraEmojis } from '@/flavours/glitch/features/emoji/normalize';

import { MfmRenderer, hasAnyMfmFn } from '../../components/mfm';

interface Options {
  valuePlain: string;
  emojis: ReturnType<typeof cleanExtraEmojis>;
  mfmEnabled: boolean;
}

export function renderSharlayanFieldValue({
  valuePlain,
  emojis,
  mfmEnabled,
}: Options): React.ReactNode | null {
  if (!mfmEnabled || !hasAnyMfmFn(valuePlain)) {
    return null;
  }

  return (
    <span className='translate' data-contents>
      <MfmRenderer text={valuePlain} emojis={emojis} isProfile />
    </span>
  );
}
