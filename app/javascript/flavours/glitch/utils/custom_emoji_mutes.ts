import type { ApiCustomEmojiMuteJSON } from 'flavours/glitch/initial_state';
import { useAppSelector } from 'flavours/glitch/store/typed_functions';

export function isCustomEmojiMuted(
  shortcode: string,
  domain: string | undefined,
  mutes: ApiCustomEmojiMuteJSON[],
): boolean {
  if (mutes.length === 0) {
    return false;
  }

  const normalizedShortcode = shortcode.toLowerCase();
  const normalizedDomain = (domain ?? '').toLowerCase();

  return mutes.some((mute) => {
    if (mute.domain && mute.domain !== normalizedDomain) {
      return false;
    }
    return normalizedShortcode.startsWith(mute.prefix.toLowerCase());
  });
}

export function useIsCustomEmojiMuted(
  shortcode: string,
  domain: string | undefined,
): boolean {
  const mutes = useAppSelector((state) => state.custom_emoji_mutes.items);
  return isCustomEmojiMuted(shortcode, domain, mutes);
}
