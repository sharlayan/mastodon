import { useCallback, useId, useState } from 'react';
import type { FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { EmojiTextInputField } from '@/mastodon/components/form_fields';
import type { BaseConfirmationModalProps } from '@/mastodon/features/ui/components/confirmation_modals';
import { ConfirmationModal } from '@/mastodon/features/ui/components/confirmation_modals';
import { patchProfile } from '@/mastodon/reducers/slices/profile_edit';
import { useAppDispatch, useAppSelector } from '@/mastodon/store';

const MAX_LENGTH = 256;

const messages = defineMessages({
  title: {
    id: 'account_edit.follow_message_modal.title',
    defaultMessage: 'Edit follow message',
  },
  placeholder: {
    id: 'account_edit.follow_message_modal.placeholder',
    defaultMessage: 'Shown to users when you accept their follow request',
  },
  save: {
    id: 'account_edit.save',
    defaultMessage: 'Save',
  },
});

export const FollowMessageModal: FC<BaseConfirmationModalProps> = ({
  onClose,
}) => {
  const intl = useIntl();
  const titleId = useId();

  const { profile: { followedMessage } = {}, isPending } = useAppSelector(
    (state) => state.profileEdit,
  );
  const [newMessage, setNewMessage] = useState(followedMessage ?? '');

  const dispatch = useAppDispatch();
  const handleSave = useCallback(() => {
    if (!isPending) {
      void dispatch(
        patchProfile({ followed_message: newMessage || null }),
      ).then(onClose);
    }
  }, [dispatch, isPending, newMessage, onClose]);

  return (
    <ConfirmationModal
      title={intl.formatMessage(messages.title)}
      titleId={titleId}
      confirm={intl.formatMessage(messages.save)}
      onConfirm={handleSave}
      onClose={onClose}
      updating={isPending}
      disabled={newMessage.length > MAX_LENGTH}
      noFocusButton
    >
      <EmojiTextInputField
        value={newMessage}
        onChange={setNewMessage}
        label=''
        aria-labelledby={titleId}
        placeholder={intl.formatMessage(messages.placeholder)}
        counterMax={MAX_LENGTH}
        // eslint-disable-next-line jsx-a11y/no-autofocus -- This is a modal, it's fine.
        autoFocus
      />
    </ConfirmationModal>
  );
};
