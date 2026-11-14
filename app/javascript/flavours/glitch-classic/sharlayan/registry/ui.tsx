import type { ReactNode } from 'react';

import { BoardAnnouncementBanner } from 'flavours/glitch-classic/features/board_announcements/banner';
import { VoiceCallBar } from 'flavours/glitch-classic/features/chat/voice/bar';
import { isWithinDriveDropzone } from 'flavours/glitch-classic/features/drive/dnd';
import { InlineComposeShell } from 'flavours/glitch-classic/features/ui/components/inline_compose_shell';
import { ContentFontSize } from 'flavours/glitch-classic/sharlayan/local_settings/content_font_size';
import { SensitiveEmojiDisplay } from 'flavours/glitch-classic/sharlayan/local_settings/sensitive_emoji_display';

export const shouldIgnoreSharlayanDropTarget = (
  target: EventTarget | null,
): boolean => isWithinDriveDropzone(target);

export const SharlayanUiExtensions = (): ReactNode => (
  <>
    <ContentFontSize />
    <SensitiveEmojiDisplay />
    <BoardAnnouncementBanner />
    <VoiceCallBar />
  </>
);

export const SharlayanColumnsAreaExtensions = InlineComposeShell;
