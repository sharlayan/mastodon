import type { ReactNode } from 'react';

import { BoardAnnouncementBanner } from 'flavours/glitch/features/board_announcements/banner';
import { isWithinDriveDropzone } from 'flavours/glitch/features/drive/dnd';
import { InlineComposeShell } from 'flavours/glitch/features/ui/components/inline_compose_shell';

export const shouldIgnoreSharlayanDropTarget = (
  target: EventTarget | null,
): boolean => isWithinDriveDropzone(target);

export const SharlayanUiExtensions = (): ReactNode => (
  <BoardAnnouncementBanner />
);

export const SharlayanColumnsAreaExtensions = InlineComposeShell;
