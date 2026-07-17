import { useMemo } from 'react';
import type { MouseEvent, ReactNode } from 'react';

import { defineMessages, useIntl } from 'react-intl';
import type { MessageDescriptor } from 'react-intl';

import { openModal } from 'flavours/glitch/actions/modal';
import { Avatar } from 'flavours/glitch/components/avatar';
import type { Button } from 'flavours/glitch/components/button';
import { Dropdown } from 'flavours/glitch/components/dropdown_menu';
import { CircleButton } from 'flavours/glitch/features/compose/components/circle_button';
import { ClipButton } from 'flavours/glitch/features/compose/components/clip_button';
import { MfmComposeHint } from 'flavours/glitch/features/compose/components/mfm_compose_hint';
import { ScheduleButton } from 'flavours/glitch/features/compose/components/schedule_button';
import type { SecondaryPrivacyButton } from 'flavours/glitch/features/compose/components/secondary_privacy_button';
import { useAccount } from 'flavours/glitch/hooks/useAccount';
import { me } from 'flavours/glitch/initial_state';
import { useAppDispatch } from 'flavours/glitch/store';

import {
  getComposeControlState,
  getSharlayanSubmitLabel,
} from './calculations';

const messages = defineMessages({
  publish: { id: 'compose_form.publish', defaultMessage: 'Post' },
  publishToot: { id: 'compose_form.publish_toot', defaultMessage: '뿌우' },
  schedule: { id: 'compose_form.schedule_submit', defaultMessage: 'Schedule' },
  saveChanges: { id: 'compose_form.save_changes', defaultMessage: 'Update' },
  reply: { id: 'compose_form.reply', defaultMessage: 'Reply' },
  profile: { id: 'column_header.profile', defaultMessage: 'Profile' },
  switchAccount: {
    id: 'navigation_bar.switch_account',
    defaultMessage: 'Switch account',
  },
  scheduled: {
    id: 'navigation_bar.scheduled',
    defaultMessage: 'Scheduled posts',
  },
});

const ComposeFormAvatar = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const account = useAccount(me);
  const acct = account?.get('acct');

  const menu = useMemo(
    () => [
      { text: intl.formatMessage(messages.profile), to: `/@${acct}` },
      {
        text: intl.formatMessage(messages.switchAccount),
        action: () =>
          dispatch(
            openModal({ modalType: 'ACCOUNT_SWITCHER', modalProps: {} }),
          ),
      },
      null,
      { text: intl.formatMessage(messages.scheduled), to: '/scheduled' },
    ],
    [intl, dispatch, acct],
  );

  if (!account) {
    return null;
  }

  return (
    <Dropdown
      items={menu}
      placement='bottom-start'
      scrollKey='compose-form-avatar'
    >
      <button type='button' className='compose-form__dropdowns__avatar'>
        <Avatar account={account} size={32} />
      </button>
    </Dropdown>
  );
};

export const SharlayanComposeSubmit = ({
  baseMessages,
  buttonComponent: SubmitButton,
  canSubmit,
  isEditing,
  isInReply,
  isSubmitting,
  onSecondarySubmit,
  scheduledAt,
  secondaryPrivacyButtonComponent: SubmitPrivacyButton,
  sideArm,
  usePublishToot,
}: {
  baseMessages: Partial<
    Record<ReturnType<typeof getSharlayanSubmitLabel>, MessageDescriptor>
  >;
  buttonComponent: typeof Button;
  canSubmit: boolean;
  isEditing?: boolean;
  isInReply?: boolean;
  isSubmitting?: boolean;
  onSecondarySubmit: (event: MouseEvent<HTMLButtonElement>) => void;
  scheduledAt?: string;
  secondaryPrivacyButtonComponent: typeof SecondaryPrivacyButton;
  sideArm?: string;
  usePublishToot?: boolean;
}) => {
  const intl = useIntl();
  const label = getSharlayanSubmitLabel({
    isEditing,
    isInReply,
    scheduledAt,
    usePublishToot,
  });

  return (
    <div className='compose-form__submit'>
      <SubmitPrivacyButton
        disabled={!canSubmit}
        privacy={sideArm}
        isEditing={isEditing}
        onClick={onSecondarySubmit}
      />
      <SubmitButton
        type='submit'
        compact
        disabled={!canSubmit}
        loading={isSubmitting}
      >
        {intl.formatMessage(baseMessages[label] ?? messages[label])}
      </SubmitButton>
    </div>
  );
};

export const SharlayanComposeControls = ({
  isEditing,
  isEditingScheduled,
  isInline,
  languageDropdown,
  onScheduleChange,
  scheduledAt,
  showScheduleButton,
  submit,
  visibilityButton,
}: {
  isEditing?: boolean;
  isEditingScheduled?: boolean;
  isInline?: boolean;
  languageDropdown: ReactNode;
  onScheduleChange: (scheduledAt: string | null) => void;
  scheduledAt?: string;
  showScheduleButton?: boolean;
  submit: ReactNode;
  visibilityButton: ReactNode;
}) => {
  const controlState = getComposeControlState({
    isEditing,
    isEditingScheduled,
    showScheduleButton,
  });

  return (
    <>
      <div className='compose-form__dropdowns__left'>
        {isInline && <ComposeFormAvatar />}
        {visibilityButton}
        <CircleButton disabled={controlState.selectionDisabled} />
        <ClipButton disabled={controlState.selectionDisabled} />
        {languageDropdown}
        {controlState.scheduleVisible && (
          <ScheduleButton
            scheduledAt={scheduledAt}
            onScheduleChange={onScheduleChange}
            disabled={controlState.scheduleDisabled}
            isEditing={controlState.scheduleEditing}
            iconOnly={false}
          />
        )}
      </div>

      <div className='compose-form__dropdowns__submit'>{submit}</div>
    </>
  );
};

export const SharlayanComposeHint = MfmComposeHint;
