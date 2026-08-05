import type { Map as ImmutableMap } from 'immutable';

import { unescapeHTML } from '@/flavours/glitch/utils/html';

export const COLLAPSE_BUTTON_CHARACTER_THRESHOLD = 0;

export const parseCharacterLimit = (value: unknown): number | null => {
  if (value === '') {
    return null;
  }

  const characterLimit = Number(value);

  return Number.isInteger(characterLimit) && characterLimit > 0
    ? characterLimit
    : null;
};

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

export const isLengthyStatus = (
  status: ImmutableMap<string, unknown>,
  characterLimitValue: unknown,
  renderedHeight: number,
  heightLimit: number,
): boolean => {
  const characterLimit = parseCharacterLimit(characterLimitValue);

  return characterLimit === null
    ? renderedHeight > heightLimit
    : isLongStatus(status, characterLimit);
};
