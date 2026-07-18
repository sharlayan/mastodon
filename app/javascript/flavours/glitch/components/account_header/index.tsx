import { useCallback } from 'react';

import classNames from 'classnames';

import { Helmet } from '@unhead/react/helmet';

import { openModal } from '@/flavours/glitch/actions/modal';
import { useLayout } from '@/flavours/glitch/hooks/useLayout';
import { useRelationship } from '@/flavours/glitch/hooks/useRelationship';
import { useVisibility } from '@/flavours/glitch/hooks/useVisibility';
import {
  autoPlayGif,
  me,
  domain as localDomain,
} from '@/flavours/glitch/initial_state';
import type { Account } from '@/flavours/glitch/models/account';
import { getAccountHidden } from '@/flavours/glitch/selectors/accounts';
import { SharlayanFollowedMessage } from '@/flavours/glitch/sharlayan/account/list_item';
import { useSharlayanEmojiInfoTooltip } from '@/flavours/glitch/sharlayan/emoji_info_tooltip';
import { useAppSelector, useAppDispatch } from '@/flavours/glitch/store';

import { AccountBio } from '../account_bio';
import { Avatar } from '../avatar';
import { AnimateEmojiProvider } from '../emoji/context';
import { FamiliarFollowers } from '../familiar_followers';

import { AccountBanners } from './banners';
import { AccountButtons } from './buttons';
import { AccountHeaderFields } from './fields';
import { AccountName } from './name';
import { AccountNote } from './note';
import { AccountNumberFields } from './number_fields';
import classes from './styles.module.scss';
import { AccountSubscriptionForm } from './subscription_form';
import { AccountTabs } from './tabs';

const titleFromAccount = (account: Account) => {
  const displayName = account.display_name;
  const acct =
    account.acct === account.username
      ? `${account.username}@${localDomain}`
      : account.acct;
  const prefix =
    displayName.trim().length === 0 ? account.username : displayName;

  return `${prefix} (@${acct})`;
};

export const AccountHeader: React.FC<{
  accountId: string;
  hideTabs?: boolean;
}> = ({ accountId, hideTabs }) => {
  const { setContainerElement, tooltip } = useSharlayanEmojiInfoTooltip();

  const dispatch = useAppDispatch();
  const account = useAppSelector((state) => state.accounts.get(accountId));
  const hidden = useAppSelector((state) => getAccountHidden(state, accountId));
  const relationship = useRelationship(accountId);

  const handleOpenAvatar = useCallback(
    (e: React.MouseEvent) => {
      if (e.button !== 0 || e.ctrlKey || e.metaKey) {
        return;
      }

      e.preventDefault();

      if (!account) {
        return;
      }

      dispatch(
        openModal({
          modalType: 'IMAGE',
          modalProps: {
            src: account.avatar,
            alt: account.avatar_description,
          },
        }),
      );
    },
    [dispatch, account],
  );

  const { layout } = useLayout();
  const { observedRef, isIntersecting } = useVisibility({
    observerOptions: {
      rootMargin: layout === 'mobile' ? '0px 0px -55px 0px' : '', // Height of bottom nav bar.
    },
  });

  if (!account) {
    return null;
  }

  const suspendedOrHidden = hidden || account.suspended;
  const isLocal = !account.acct.includes('@');
  const isMe = me && account.id === me;

  return (
    <div ref={setContainerElement}>
      <AccountBanners account={account} />

      <AnimateEmojiProvider
        className={classNames(!!account.moved && classes.moved)}
      >
        <div className={classes.header}>
          {!suspendedOrHidden && (
            <img
              src={autoPlayGif ? account.header : account.header_static}
              alt={account.header_description}
              className='parallax'
            />
          )}
        </div>

        <div className={classes.barWrapper}>
          <div className={classes.avatarWrapper}>
            <a
              href={account.avatar}
              rel='noopener'
              target='_blank'
              onClick={handleOpenAvatar}
            >
              <Avatar
                className={classes.avatar}
                account={suspendedOrHidden ? undefined : account}
                alt={account.avatar_description}
                size={80}
              />
            </a>
          </div>

          <div className={classes.displayNameWrapper}>
            <AccountName accountId={accountId} />
            <AccountButtons
              accountId={accountId}
              className={classes.buttonsDesktop}
              noShare={!isMe || 'share' in navigator}
              forceMenu={'share' in navigator}
            />
          </div>

          <AccountNumberFields accountId={accountId} />

          {!isMe && !suspendedOrHidden && (
            <FamiliarFollowers
              accountId={accountId}
              className={classes.familiarFollowers}
            />
          )}

          {!suspendedOrHidden && (
            <div className={classes.bioButtonsWrapper}>
              {me && account.id !== me && <AccountNote accountId={accountId} />}

              <AccountBio showDropdown accountId={accountId} />

              <AccountHeaderFields accountId={accountId} />

              <SharlayanFollowedMessage
                account={account}
                relationship={relationship}
                className='account__header__follow-message'
                labelClassName='account__header__follow-message__label'
              />

              {!me && account.email_subscriptions && (
                <AccountSubscriptionForm accountId={accountId} />
              )}
            </div>
          )}

          <AccountButtons
            className={classNames(
              classes.buttonsMobile,
              !isIntersecting && classes.buttonsMobileIsStuck,
            )}
            accountId={accountId}
            noShare
          />
        </div>
      </AnimateEmojiProvider>

      {!hideTabs && !hidden && <AccountTabs />}
      <div ref={observedRef} />

      <Helmet>
        <title>{titleFromAccount(account)}</title>
        <meta
          name='robots'
          content={isLocal && !account.noindex ? 'all' : 'noindex'}
        />
        <link rel='canonical' href={account.url} />
      </Helmet>
      {tooltip}
    </div>
  );
};
