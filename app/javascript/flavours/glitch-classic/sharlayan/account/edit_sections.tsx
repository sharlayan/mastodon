import type { FC } from 'react';
import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { openModal } from '@/flavours/glitch-classic/actions/modal';
import {
  avatarDecorationsEnabled,
  avatarDecorationsLocalOnlyView,
} from '@/flavours/glitch-classic/initial_state';
import { useAppDispatch } from '@/flavours/glitch-classic/store';

import { EditButton } from '../../features/account_edit/components/edit_button';
import { AccountEditSection } from '../../features/account_edit/components/section';

import { parseBirthday } from './birthday';

const messages = defineMessages({
  followMessageTitle: {
    id: 'account_edit.follow_message.title',
    defaultMessage: 'Follow message',
  },
  followMessagePlaceholder: {
    id: 'account_edit.follow_message.placeholder',
    defaultMessage:
      'Add a message shown to users when you accept their follow request.',
  },
  followMessageEditLabel: {
    id: 'account_edit.follow_message.edit_label',
    defaultMessage: 'Edit follow message',
  },
  decorationsTitle: {
    id: 'account_edit.decorations.title',
    defaultMessage: 'Profile decorations',
  },
  decorationsPlaceholder: {
    id: 'account_edit.decorations.placeholder',
    defaultMessage: 'Add decorative overlays to your avatar.',
  },
  decorationsEditLabel: {
    id: 'account_edit.decorations.edit_label',
    defaultMessage: 'Edit decorations',
  },
  birthdayTitle: {
    id: 'account_edit.birthday.title',
    defaultMessage: 'Birthday',
  },
  birthdayPlaceholder: {
    id: 'account_edit.birthday.placeholder',
    defaultMessage:
      'Add your birthday and choose whether others can see it on your profile.',
  },
  birthdayEditLabel: {
    id: 'account_edit.birthday.edit_label',
    defaultMessage: 'Edit birthday',
  },
  birthdayPublic: {
    id: 'account_edit.birthday.public',
    defaultMessage: 'Shown on your profile',
  },
  birthdayPrivate: {
    id: 'account_edit.birthday.private',
    defaultMessage: 'Only visible to you',
  },
});

interface Props {
  followedMessage?: string | null;
  decorationCount: number;
  birthday?: string | null;
  showBirthday?: boolean;
}

export const SharlayanAccountEditSections: FC<Props> = ({
  followedMessage,
  decorationCount,
  birthday,
  showBirthday,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const handleFollowMessageEdit = useCallback(() => {
    dispatch(
      openModal({ modalType: 'ACCOUNT_EDIT_FOLLOW_MESSAGE', modalProps: {} }),
    );
  }, [dispatch]);
  const handleBirthdayEdit = useCallback(() => {
    dispatch(openModal({ modalType: 'ACCOUNT_EDIT_BIRTHDAY', modalProps: {} }));
  }, [dispatch]);
  const handleDecorationsEdit = useCallback(() => {
    dispatch(
      openModal({ modalType: 'ACCOUNT_EDIT_DECORATION', modalProps: {} }),
    );
  }, [dispatch]);

  const hasFollowMessage = !!followedMessage;
  const birthdayDate = parseBirthday(birthday);
  const hasDecorations = decorationCount > 0;

  return (
    <>
      <AccountEditSection
        title={messages.followMessageTitle}
        description={messages.followMessagePlaceholder}
        showDescription={!hasFollowMessage}
        buttons={
          <EditButton
            onClick={handleFollowMessageEdit}
            label={intl.formatMessage(messages.followMessageEditLabel)}
            icon={hasFollowMessage}
          />
        }
      >
        {hasFollowMessage && <span>{followedMessage}</span>}
      </AccountEditSection>

      <AccountEditSection
        title={messages.birthdayTitle}
        description={messages.birthdayPlaceholder}
        showDescription={!birthdayDate}
        buttons={
          <EditButton
            onClick={handleBirthdayEdit}
            label={intl.formatMessage(messages.birthdayEditLabel)}
            icon={!!birthdayDate}
          />
        }
      >
        {birthdayDate && (
          <span>
            {intl.formatDate(birthdayDate, {
              year: 'numeric',
              month: 'long',
              day: 'numeric',
              timeZone: 'UTC',
            })}
            {' · '}
            {intl.formatMessage(
              showBirthday ? messages.birthdayPublic : messages.birthdayPrivate,
            )}
          </span>
        )}
      </AccountEditSection>

      {avatarDecorationsEnabled && !avatarDecorationsLocalOnlyView && (
        <AccountEditSection
          title={messages.decorationsTitle}
          description={messages.decorationsPlaceholder}
          showDescription={!hasDecorations}
          buttons={
            <EditButton
              onClick={handleDecorationsEdit}
              label={intl.formatMessage(messages.decorationsEditLabel)}
              icon={hasDecorations}
            />
          }
        >
          {hasDecorations && (
            <span>
              {decorationCount === 1
                ? intl.formatMessage(
                    {
                      id: 'account_edit.decorations.count_one',
                      defaultMessage: '{count} decoration',
                    },
                    { count: decorationCount },
                  )
                : intl.formatMessage(
                    {
                      id: 'account_edit.decorations.count_other',
                      defaultMessage: '{count} decorations',
                    },
                    { count: decorationCount },
                  )}
            </span>
          )}
        </AccountEditSection>
      )}
    </>
  );
};
