interface ComposeControlOptions {
  isEditing?: boolean;
  isEditingScheduled?: boolean;
  showScheduleButton?: boolean;
}

export function shouldShowScheduleButton(
  showScheduleButton?: boolean,
  isEditingScheduled?: boolean,
) {
  return Boolean(showScheduleButton || isEditingScheduled);
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
