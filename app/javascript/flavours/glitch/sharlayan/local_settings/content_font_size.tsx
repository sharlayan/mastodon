import { useEffect } from 'react';

import type { Map as ImmutableMap } from 'immutable';

import { initialState } from 'flavours/glitch/initial_state';
import { useAppSelector } from 'flavours/glitch/store';

export const CONTENT_FONT_SIZES = [
  'medium',
  'large',
  'x_large',
  'xx_large',
] as const;

export type ContentFontSize = (typeof CONTENT_FONT_SIZES)[number];

export const DEFAULT_CONTENT_FONT_SIZE: ContentFontSize = 'medium';

export const applyContentFontSize = (value: unknown) => {
  const { classList } = document.documentElement;

  CONTENT_FONT_SIZES.forEach((size) => {
    classList.toggle(
      `content-font-size__${size}`,
      size !== DEFAULT_CONTENT_FONT_SIZE && size === value,
    );
  });
};

export const applyStoredContentFontSize = () => {
  const localSettings = initialState?.local_settings as
    | Record<string, unknown>
    | undefined;

  applyContentFontSize(localSettings?.content_font_size);
};

export const ContentFontSize: React.FC = () => {
  const contentFontSize = useAppSelector(
    (state) =>
      (state.local_settings as ImmutableMap<string, unknown>).get(
        'content_font_size',
        DEFAULT_CONTENT_FONT_SIZE,
      ) as string,
  );

  useEffect(() => {
    applyContentFontSize(contentFontSize);
  }, [contentFontSize]);

  return null;
};
