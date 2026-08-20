import { useCallback } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import type { Map as ImmutableMap } from 'immutable';

import {
  PenNibIcon,
  HouseIcon,
  MagnifyingGlassIcon,
  BellIcon,
  BellRingingIcon,
  ChatCircleIcon,
  BookmarkSimpleIcon,
  BankIcon,
} from '@phosphor-icons/react';

import { useIdentity } from '@/flavours/glitch/identity_context';
import { openNewComposer } from '@/flavours/glitch/reducers/slices/composer';
import { selectUnreadNotificationGroupsCount } from '@/flavours/glitch/selectors/notifications';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

import { NavigationAccountCard } from './account_card';
import { NavigationFooterLinks } from './footer_links';
import { NavigationHeader } from './header';
import { NavigationLink } from './navigation_link';
import classes from './styles.module.scss';

const messages = defineMessages({
  main: {
    id: 'navigation_bar.main',
    defaultMessage: 'Main',
    description:
      'Label for the main navigation; should not contain the word "navigation".',
  },
});

export const RedesignNavigationPanel: React.FC<{ siteName?: string }> = ({
  siteName,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { signedIn } = useIdentity();
  const notificationsCount = useAppSelector(
    selectUnreadNotificationGroupsCount,
  );
  const useMyArchive = useAppSelector(
    (state) =>
      (state.local_settings as ImmutableMap<string, unknown>).get(
        'use_my_archive',
        false,
      ) as boolean,
  );

  const openComposer = useCallback(() => {
    dispatch(openNewComposer({ type: 'post' }));
  }, [dispatch]);

  return (
    <nav
      className={classes.root}
      aria-label={intl.formatMessage(messages.main)}
    >
      <NavigationHeader siteName={siteName} />
      {signedIn && (
        <>
          <ul className={classes.list}>
            <NavigationLink
              withSpaceAfter
              as='button'
              onClick={openComposer}
              iconComponent={PenNibIcon}
            >
              <FormattedMessage
                id='tabs_bar.publish'
                defaultMessage='New Post'
              />
            </NavigationLink>
            <NavigationLink to='/home' iconComponent={HouseIcon}>
              <FormattedMessage id='tabs_bar.home' defaultMessage='Home' />
            </NavigationLink>
            <NavigationLink to='/explore' iconComponent={MagnifyingGlassIcon}>
              <FormattedMessage
                id='tabs_bar.explore'
                defaultMessage='Explore'
              />
            </NavigationLink>
            <NavigationLink
              to='/notifications'
              iconComponent={
                notificationsCount > 0 ? BellRingingIcon : BellIcon
              }
              badgeCount={notificationsCount}
            >
              <FormattedMessage
                id='tabs_bar.notifications'
                defaultMessage='Notifications'
              />
            </NavigationLink>
            <NavigationLink to='/conversations' iconComponent={ChatCircleIcon}>
              <FormattedMessage
                id='tabs_bar.messages'
                defaultMessage='Messages'
                description='Message refers to a direct message. For languages where this is confusing, "chat" or "direct message" can be used.'
              />
            </NavigationLink>
            {useMyArchive ? (
              <NavigationLink
                to='/favourites'
                iconComponent={BankIcon}
                activePaths={[
                  '/favourites',
                  '/bookmarks',
                  '/reactions',
                  '/clips',
                ]}
              >
                <FormattedMessage
                  id='navigation_bar.my_archive'
                  defaultMessage='My archive'
                />
              </NavigationLink>
            ) : (
              <NavigationLink
                to='/bookmarks'
                iconComponent={BookmarkSimpleIcon}
              >
                <FormattedMessage id='tabs_bar.saved' defaultMessage='Saved' />
              </NavigationLink>
            )}
          </ul>
          <footer className={classes.footer}>
            <NavigationAccountCard />
            <NavigationFooterLinks siteName={siteName} />
          </footer>
        </>
      )}
    </nav>
  );
};
