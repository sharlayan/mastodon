import type { RecordOf, List as ImmutableList } from 'immutable';
import { Record as ImmutableRecord, isList } from 'immutable';

import type { ApiCustomEmojiJSON } from 'flavours/glitch/api_types/custom_emoji';

type CustomEmojiShape = Required<
  Omit<ApiCustomEmojiJSON, 'aliases' | 'license'>
> & {
  aliases: string[];
  license: string;
};
export type CustomEmoji = RecordOf<CustomEmojiShape>;

export const CustomEmojiFactory = ImmutableRecord<CustomEmojiShape>({
  shortcode: '',
  static_url: '',
  url: '',
  category: '',
  featured: false,
  visible_in_picker: false,
  aliases: [],
  license: '',
});

export type EmojiMap = Record<string, ApiCustomEmojiJSON>;

export function makeEmojiMap(
  emojis: ApiCustomEmojiJSON[] | ImmutableList<CustomEmoji>,
) {
  if (isList(emojis)) {
    return emojis.reduce<EmojiMap>((obj, emoji) => {
      obj[`:${emoji.shortcode}:`] = emoji.toJS() as ApiCustomEmojiJSON;
      return obj;
    }, {});
  } else
    return emojis.reduce<EmojiMap>((obj, emoji) => {
      obj[`:${emoji.shortcode}:`] = emoji;
      return obj;
    }, {});
}
