import type { Map as ImmutableMap } from 'immutable';

import { unescapeHTML } from '@/flavours/glitch/utils/html';

export const COLLAPSE_BUTTON_CHARACTER_THRESHOLD = 0;

export const isLongStatus = (
  status: ImmutableMap<string, unknown>,
  characterLimit: number,
): boolean => {
  const contentHtml = status.get('contentHtml');
  const content = status.get('content');
  const plainText = unescapeHTML(
    typeof contentHtml === 'string'
      ? contentHtml
      : typeof content === 'string'
        ? content
        : '',
  );

  return Array.from(plainText).length >= characterLimit;
};

export const shouldShowCollapseButton = (
  status: ImmutableMap<string, unknown>,
  collapsed: boolean,
  characterLimit: number | null,
): boolean =>
  collapsed || characterLimit === null || isLongStatus(status, characterLimit);
