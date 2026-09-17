import { useEffect } from 'react';

import { initialState } from 'flavours/glitch/initial_state';
import { useAppSelector } from 'flavours/glitch/store';

export const SENSITIVE_EMOJI_DISPLAY_VALUES = [
  'show',
  'grayscale',
  'hide',
] as const;

export const applySensitiveEmojiDisplay = (value: unknown) => {
  const normalized = SENSITIVE_EMOJI_DISPLAY_VALUES.includes(
    value as (typeof SENSITIVE_EMOJI_DISPLAY_VALUES)[number],
  )
    ? value
    : 'show';

  for (const mode of SENSITIVE_EMOJI_DISPLAY_VALUES) {
    document.documentElement.classList.toggle(
      `sensitive-emoji-display--${mode}`,
      mode === normalized,
    );
  }
};

export const applyStoredSensitiveEmojiDisplay = () => {
  const localSettings = initialState?.local_settings as
    | Record<string, unknown>
    | undefined;

  applySensitiveEmojiDisplay(localSettings?.sensitive_emoji_display);
};

export const SensitiveEmojiDisplay = () => {
  const value = useAppSelector(
    (state) =>
      state.local_settings.get('sensitive_emoji_display', 'show') as string,
  );

  useEffect(() => {
    applySensitiveEmojiDisplay(value);
  }, [value]);

  return null;
};
