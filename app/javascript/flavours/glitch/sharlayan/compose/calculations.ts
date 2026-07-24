import { length } from 'stringz';

import { overflowStart } from 'flavours/glitch/features/compose/util/overflow';

export type SubmitLabel =
  | 'publish'
  | 'publishToot'
  | 'reply'
  | 'saveChanges'
  | 'schedule';

interface SubmitLabelOptions {
  isEditing?: boolean;
  isInReply?: boolean;
  scheduledAt?: string | null;
  usePublishToot?: boolean;
}

interface CanSubmitOptions {
  fullText: string;
  isChangingUpload?: boolean;
  isSubmitting?: boolean;
  isUploading?: boolean;
  maxChars: number;
}

interface OverflowOptions {
  countedText: string;
  maxChars: number;
  spoiler?: boolean;
  spoilerText?: string;
  text: string;
}

interface ComposeControlOptions {
  isEditing?: boolean;
  isEditingScheduled?: boolean;
  showScheduleButton?: boolean;
}

export function getSharlayanSubmitLabel({
  isEditing,
  isInReply,
  scheduledAt,
  usePublishToot,
}: SubmitLabelOptions): SubmitLabel {
  if (isEditing) {
    return 'saveChanges';
  }

  if (scheduledAt) {
    return 'schedule';
  }

  if (isInReply) {
    return 'reply';
  }

  return usePublishToot ? 'publishToot' : 'publish';
}

export function canSubmitCompose({
  fullText,
  isChangingUpload,
  isSubmitting,
  isUploading,
  maxChars,
}: CanSubmitOptions) {
  return !(
    isSubmitting ||
    isUploading ||
    isChangingUpload ||
    length(fullText) > maxChars
  );
}

export function getComposeOverflowStart({
  countedText,
  maxChars,
  spoiler,
  spoilerText = '',
  text,
}: OverflowOptions) {
  if (length(countedText) <= maxChars) {
    return -1;
  }

  return overflowStart(
    text,
    maxChars - (spoiler ? length(spoilerText) : 0),
  ) as number;
}

export function shouldShowScheduleButton(
  showScheduleButton?: boolean,
  isEditingScheduled?: boolean,
) {
  return Boolean(showScheduleButton || isEditingScheduled);
}

export function shouldShowComposeLanguage(hideComposeLanguage?: boolean) {
  return !hideComposeLanguage;
}

export function getComposeControlState({
  isEditing,
  isEditingScheduled,
  showScheduleButton,
}: ComposeControlOptions) {
  return {
    scheduleDisabled: Boolean(isEditing && !isEditingScheduled),
    scheduleEditing: Boolean(isEditing && !isEditingScheduled),
    scheduleVisible: shouldShowScheduleButton(
      showScheduleButton,
      isEditingScheduled,
    ),
    selectionDisabled: Boolean(isEditing),
  };
}
