import { useMemo, useState } from 'react';

import { EmojiInfoTooltip } from '@/flavours/glitch/components/emoji_info_tooltip';

export function useSharlayanEmojiInfoTooltip() {
  const [containerElement, setContainerElement] = useState<HTMLElement | null>(
    null,
  );

  const containerRef = useMemo(
    () => ({ current: containerElement }),
    [containerElement],
  );

  const tooltip = <EmojiInfoTooltip containerRef={containerRef} enabled />;

  return { setContainerElement, tooltip };
}
