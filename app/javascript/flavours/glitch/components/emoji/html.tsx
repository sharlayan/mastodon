import { useMemo } from 'react';

import type { CustomEmojiMapArg } from '@/flavours/glitch/features/emoji/types';
import type {
  AllowedTagsType,
  OnAttributeHandler,
  OnElementHandler,
} from '@/flavours/glitch/utils/html';
import { htmlStringToComponents } from '@/flavours/glitch/utils/html';
import { polymorphicForwardRef } from '@/types/polymorphic';

import { AnimateEmojiProvider, CustomEmojiProvider } from './context';
import { textToEmojis } from './index';

export interface EmojiHTMLProps {
  htmlString: string;
  extraEmojis?: CustomEmojiMapArg;
  className?: string;
  onElement?: OnElementHandler;
  onAttribute?: OnAttributeHandler;
  allowedTags?: AllowedTagsType;
}

export const EmojiHTML = polymorphicForwardRef<'div', EmojiHTMLProps>(
  (
    { extraEmojis, htmlString, onElement, onAttribute, allowedTags, ...props },
    ref,
  ) => {
    const contents = useMemo(
      () =>
        htmlStringToComponents(htmlString, {
          onText: textToEmojis,
          onElement,
          onAttribute,
          allowedTags,
        }),
      [htmlString, onAttribute, onElement, allowedTags],
    );

    return (
      <CustomEmojiProvider emojis={extraEmojis}>
        <AnimateEmojiProvider {...props} ref={ref}>
          {contents}
        </AnimateEmojiProvider>
      </CustomEmojiProvider>
    );
  },
);
EmojiHTML.displayName = 'EmojiHTML';
