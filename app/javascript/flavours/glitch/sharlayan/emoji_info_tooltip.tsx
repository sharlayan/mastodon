import { useState } from 'react';

import { EmojiInfoTooltip } from '@/flavours/glitch/components/emoji_info_tooltip';

export function useSharlayanEmojiInfoTooltip() {
  const [containerElement, setContainerElement] = useState<HTMLElement | null>(
    null,
  );

  const tooltip = (
    <EmojiInfoTooltip containerRef={{ current: containerElement }} enabled />
  );

  return { setContainerElement, tooltip };
}
