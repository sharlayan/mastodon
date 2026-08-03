import type { FC } from 'react';
import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { openModal } from '@/flavours/glitch/actions/modal';
import {
  avatarDecorationsEnabled,
  avatarDecorationsLocalOnlyView,
} from '@/flavours/glitch/initial_state';
import { useAppDispatch } from '@/flavours/glitch/store';

import { EditButton } from '../../features/account_edit/components/edit_button';
import { AccountEditSection } from '../../features/account_edit/components/section';

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
});

interface Props {
  followedMessage?: string | null;
  decorationCount: number;
}

export const SharlayanAccountEditSections: FC<Props> = ({
  followedMessage,
  decorationCount,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const handleFollowMessageEdit = useCallback(() => {
    dispatch(
      openModal({ modalType: 'ACCOUNT_EDIT_FOLLOW_MESSAGE', modalProps: {} }),
    );
  }, [dispatch]);
  const handleDecorationsEdit = useCallback(() => {
    dispatch(
      openModal({ modalType: 'ACCOUNT_EDIT_DECORATION', modalProps: {} }),
    );
  }, [dispatch]);

  const hasFollowMessage = !!followedMessage;
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
