import type { ReactNode } from 'react';

import { BoardAnnouncementBanner } from 'flavours/glitch/features/board_announcements/banner';
import { isWithinDriveDropzone } from 'flavours/glitch/features/drive/dnd';
import { InlineComposeShell } from 'flavours/glitch/features/ui/components/inline_compose_shell';
import { ContentFontSize } from 'flavours/glitch/sharlayan/local_settings/content_font_size';
import { SensitiveEmojiDisplay } from 'flavours/glitch/sharlayan/local_settings/sensitive_emoji_display';

export const shouldIgnoreSharlayanDropTarget = (
  target: EventTarget | null,
): boolean => isWithinDriveDropzone(target);

export const SharlayanUiExtensions = (): ReactNode => (
  <>
    <ContentFontSize />
    <SensitiveEmojiDisplay />
    <BoardAnnouncementBanner />
  </>
);

export const SharlayanColumnsAreaExtensions = InlineComposeShell;
