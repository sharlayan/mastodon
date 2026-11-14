import { useCallback, useId, useState } from 'react';
import type { ChangeEvent, FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import {
  FormStack,
  TextInputField,
  ToggleField,
} from '@/flavours/glitch-classic/components/form_fields';
import type { BaseConfirmationModalProps } from '@/flavours/glitch-classic/features/ui/components/confirmation_modals';
import { ConfirmationModal } from '@/flavours/glitch-classic/features/ui/components/confirmation_modals';
import { patchProfile } from '@/flavours/glitch-classic/reducers/slices/profile_edit';
import {
  useAppDispatch,
  useAppSelector,
} from '@/flavours/glitch-classic/store';

import { parseBirthday } from './birthday';

const messages = defineMessages({
  title: {
    id: 'account_edit.birthday_modal.title',
    defaultMessage: 'Edit birthday',
  },
  dateLabel: {
    id: 'account_edit.birthday_modal.date_label',
    defaultMessage: 'Birthday',
  },
  dateHint: {
    id: 'account_edit.birthday_modal.date_hint',
    defaultMessage: 'Leave empty to remove your birthday.',
  },
  showLabel: {
    id: 'account_edit.birthday_modal.show_label',
    defaultMessage: 'Show my birthday on my profile',
  },
  showHint: {
    id: 'account_edit.birthday_modal.show_hint',
    defaultMessage:
      'When turned off, only you can see it. This also applies to Misskey-compatible apps.',
  },
  save: {
    id: 'account_edit.save',
    defaultMessage: 'Save',
  },
});

const todayValue = () => new Date().toISOString().slice(0, 10);

export const BirthdayModal: FC<BaseConfirmationModalProps> = ({ onClose }) => {
  const intl = useIntl();
  const titleId = useId();
  const dispatch = useAppDispatch();
  const { profile, isPending } = useAppSelector((state) => state.profileEdit);

  const [birthday, setBirthday] = useState(profile?.birthday ?? '');
  const [showBirthday, setShowBirthday] = useState(
    profile?.showBirthday ?? false,
  );

  const handleDateChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setBirthday(e.target.value);
  }, []);

  const handleShowChange = useCallback(() => {
    setShowBirthday((value) => !value);
  }, []);

  const valid = birthday === '' || parseBirthday(birthday) !== null;

  const handleSave = useCallback(() => {
    if (isPending || !valid) return;

    void dispatch(patchProfile({ birthday, show_birthday: showBirthday })).then(
      onClose,
    );
  }, [dispatch, isPending, valid, birthday, showBirthday, onClose]);

  return (
    <ConfirmationModal
      title={intl.formatMessage(messages.title)}
      titleId={titleId}
      confirm={intl.formatMessage(messages.save)}
      onConfirm={handleSave}
      onClose={onClose}
      updating={isPending}
      disabled={!valid}
      noFocusButton
    >
      <FormStack>
        <TextInputField
          type='date'
          value={birthday}
          max={todayValue()}
          min='1900-01-01'
          onChange={handleDateChange}
          label={intl.formatMessage(messages.dateLabel)}
          hint={intl.formatMessage(messages.dateHint)}
        />

        <ToggleField
          checked={showBirthday}
          onChange={handleShowChange}
          label={intl.formatMessage(messages.showLabel)}
          hint={intl.formatMessage(messages.showHint)}
        />
      </FormStack>
    </ConfirmationModal>
  );
};
