import { useCallback, useMemo } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import classNames from 'classnames';

import { EmojiHTML } from '@/flavours/glitch-classic/components/emoji/html';
import MoreHorizIcon from '@/material-icons/400-24px/more_horiz.svg?react';
import {
  blockAccount,
  unblockAccount,
  muteAccount,
  unmuteAccount,
  followAccountSuccess,
  unpinAccount,
  pinAccount,
} from 'flavours/glitch-classic/actions/accounts';
import { showAlertForError } from 'flavours/glitch-classic/actions/alerts';
import { openModal } from 'flavours/glitch-classic/actions/modal';
import { initMuteModal } from 'flavours/glitch-classic/actions/mutes';
import { apiFollowAccount } from 'flavours/glitch-classic/api/accounts';
import { AccountFollowersCount } from 'flavours/glitch-classic/components/account_followers_count';
import { Avatar } from 'flavours/glitch-classic/components/avatar';
import { VerifiedBadge } from 'flavours/glitch-classic/components/badge';
import { Button } from 'flavours/glitch-classic/components/button';
import { DisplayName } from 'flavours/glitch-classic/components/display_name';
import { Dropdown } from 'flavours/glitch-classic/components/dropdown_menu';
import { FollowButton } from 'flavours/glitch-classic/components/follow_button';
import { RelativeTimestamp } from 'flavours/glitch-classic/components/relative_timestamp';
import { Skeleton } from 'flavours/glitch-classic/components/skeleton';
import { useIdentity } from 'flavours/glitch-classic/identity_context';
import { me } from 'flavours/glitch-classic/initial_state';
import type { MenuItem } from 'flavours/glitch-classic/models/dropdown_menu';
import { useAppSelector, useAppDispatch } from 'flavours/glitch-classic/store';

import { Permalink } from '../permalink';

const messages = defineMessages({
  follow: { id: 'account.follow', defaultMessage: 'Follow' },
  unfollow: { id: 'account.unfollow', defaultMessage: 'Unfollow' },
  cancel_follow_request: {
    id: 'account.cancel_follow_request',
    defaultMessage: 'Withdraw follow request',
  },
  unblock: { id: 'account.unblock_short', defaultMessage: 'Unblock' },
  unmute: { id: 'account.unmute_short', defaultMessage: 'Unmute' },
  mute_notifications: {
    id: 'account.mute_notifications_short',
    defaultMessage: 'Mute notifications',
  },
  unmute_notifications: {
    id: 'account.unmute_notifications_short',
    defaultMessage: 'Unmute notifications',
  },
  mute: { id: 'account.mute_short', defaultMessage: 'Mute' },
  block: { id: 'account.block_short', defaultMessage: 'Block' },
  more: { id: 'status.more', defaultMessage: 'More' },
  addToLists: {
    id: 'account.add_or_remove_from_list',
    defaultMessage: 'Add or Remove from lists',
  },
  openOriginalPage: {
    id: 'account.open_original_page',
    defaultMessage: 'Open original page',
  },
});

interface AccountProps {
  size?: number;
  id: string;
  hidden?: boolean;
  minimal?: boolean;
  defaultAction?: 'block' | 'mute';
  withBio?: boolean;
  withMenu?: boolean;
  withBorder?: boolean;
  extraAccountInfo?: React.ReactNode;
  className?: string;
  children?: React.ReactNode;
  reference?: string;
}

export const Account: React.FC<AccountProps> = ({
  id,
  size = 46,
  hidden,
  minimal,
  defaultAction,
  withBio,
  withMenu = true,
  withBorder = true,
  extraAccountInfo,
  className,
  children,
  reference,
}) => {
  const intl = useIntl();
  const { signedIn } = useIdentity();
  const account = useAppSelector((state) => state.accounts.get(id));
  const relationship = useAppSelector((state) => state.relationships.get(id));
  const dispatch = useAppDispatch();
  const accountUrl = account?.url;
  const isRemote = account?.acct !== account?.username;

  const handleBlock = useCallback(() => {
    if (relationship?.blocking) {
      dispatch(unblockAccount(id));
    } else {
      dispatch(blockAccount(id));
    }
  }, [dispatch, id, relationship]);

  const handleMute = useCallback(() => {
    if (relationship?.muting) {
      dispatch(unmuteAccount(id));
    } else {
      dispatch(initMuteModal(account));
    }
  }, [dispatch, id, account, relationship]);

  const menu = useMemo(() => {
    let arr: MenuItem[] = [];

    if (defaultAction === 'mute') {
      const handleMuteNotifications = () => {
        dispatch(muteAccount(id, true));
      };

      const handleUnmuteNotifications = () => {
        dispatch(muteAccount(id, false));
      };

      arr = [
        {
          text: intl.formatMessage(
            relationship?.muting_notifications
              ? messages.unmute_notifications
              : messages.mute_notifications,
          ),
          action: relationship?.muting_notifications
            ? handleUnmuteNotifications
            : handleMuteNotifications,
        },
      ];
    } else if (defaultAction !== 'block') {
      if (isRemote && accountUrl) {
        arr.push({
          text: intl.formatMessage(messages.openOriginalPage),
          href: accountUrl,
        });
      }

      if (signedIn) {
        const handleAddToLists = () => {
          const openAddToListModal = () => {
            dispatch(
              openModal({
                modalType: 'LIST_ADDER',
                modalProps: {
                  accountId: id,
                },
              }),
            );
          };
          if (relationship?.following || relationship?.requested || id === me) {
            openAddToListModal();
          } else {
            dispatch(
              openModal({
                modalType: 'CONFIRM_FOLLOW_TO_LIST',
                modalProps: {
                  accountId: id,
                  onConfirm: () => {
                    apiFollowAccount(id, { ref: reference })
                      .then((relationship) => {
                        dispatch(
                          followAccountSuccess({
                            relationship,
                            alreadyFollowing: false,
                          }),
                        );
                        openAddToListModal();
                      })
                      .catch((err: unknown) => {
                        dispatch(showAlertForError(err));
                      });
                  },
                },
              }),
            );
          }
        };

        arr.push({
          text: intl.formatMessage(messages.addToLists),
          action: handleAddToLists,
        });

        if (id !== me && (relationship?.following || relationship?.requested)) {
          const handleEndorseToggle = () => {
            if (relationship.endorsed) {
              dispatch(unpinAccount(id));
            } else {
              dispatch(pinAccount(id));
            }
          };
          arr.push({
            text: intl.formatMessage(
              // Defined in features/account_timeline/components/account_header.tsx
              relationship.endorsed
                ? { id: 'account.unendorse' }
                : { id: 'account.endorse' },
            ),
            action: handleEndorseToggle,
          });
        }
      }
    }

    return arr;
  }, [
    dispatch,
    intl,
    id,
    accountUrl,
    relationship,
    defaultAction,
    isRemote,
    signedIn,
    reference,
  ]);

  if (hidden) {
    return (
      <>
        {account?.display_name}
        {account?.username}
      </>
    );
  }

  let button: React.ReactNode;
  let dropdown: React.ReactNode;

  if (menu.length > 0 && withMenu) {
    dropdown = (
      <Dropdown
        items={menu}
        icon='ellipsis-h'
        iconComponent={MoreHorizIcon}
        title={intl.formatMessage(messages.more)}
      />
    );
  }

  if (defaultAction === 'block') {
    button = (
      <Button
        text={intl.formatMessage(
          relationship?.blocking ? messages.unblock : messages.block,
        )}
        onClick={handleBlock}
      />
    );
  } else if (defaultAction === 'mute') {
    button = (
      <Button
        text={intl.formatMessage(
          relationship?.muting ? messages.unmute : messages.mute,
        )}
        onClick={handleMute}
      />
    );
  } else {
    button = <FollowButton accountId={id} reference={reference} />;
  }

  let muteTimeRemaining: React.ReactNode;

  if (account?.mute_expires_at) {
    muteTimeRemaining = (
      <>
        · <RelativeTimestamp hasFuture timestamp={account.mute_expires_at} />
      </>
    );
  }

  let verification: React.ReactNode;

  const firstVerifiedField = account?.fields.find((item) => !!item.verified_at);

  if (firstVerifiedField) {
    verification = <VerifiedBadge link={firstVerifiedField.value} />;
  }

  return (
    <div
      className={classNames('account', className, {
        'account--minimal': minimal,
        'account--without-border': !withBorder,
      })}
    >
      <div
        className={classNames('account__wrapper', {
          'account__wrapper--with-bio': account && withBio,
        })}
      >
        <div className='account__info-wrapper'>
          <Permalink
            className='account__display-name focusable'
            title={account?.acct}
            href={account?.url}
            to={{ pathname: `/@${account?.acct}`, state: { reference } }}
            data-hover-card-account={id}
            data-hover-card-reference={reference}
          >
            <div className='account__avatar-wrapper'>
              {account ? (
                <Avatar account={account} size={size} />
              ) : (
                <Skeleton width={size} height={size} />
              )}
            </div>

            <div className='account__contents'>
              <DisplayName account={account} />

              {!minimal && (
                <div className='account__details'>
                  {account ? (
                    <>
                      <AccountFollowersCount
                        value={account.followers_count}
                        withLabel
                      />{' '}
                      {verification} {muteTimeRemaining}
                    </>
                  ) : (
                    <Skeleton width='7ch' />
                  )}
                </div>
              )}
            </div>
          </Permalink>

          {account &&
            withBio &&
            (account.note.length > 0 ? (
              <EmojiHTML
                className='account__note translate'
                htmlString={account.note_emojified}
                extraEmojis={account.emojis}
              />
            ) : (
              <div className='account__note account__note--missing'>
                <FormattedMessage
                  id='account.no_bio'
                  defaultMessage='No description provided.'
                />
              </div>
            ))}

          {extraAccountInfo}
        </div>

        {!minimal && (
          <div className='account__relationship'>
            {dropdown}
            {button}
          </div>
        )}

        {children}
      </div>
    </div>
  );
};
