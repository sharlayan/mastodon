import { useCallback } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';

import {
  CaretLineRightIcon,
  MagnifyingGlassIcon,
  PenNibIcon,
  PlusIcon,
  RssSimpleIcon,
  ArrowUpRightIcon,
  HashIcon,
  CaretLineLeftIcon,
  PuzzlePieceIcon,
} from '@phosphor-icons/react';

import { IconButton } from '@/flavours/glitch/components/button';
import {
  Menu,
  MenuItem,
  MenuItemGroup,
  MenuItemLink,
  MenuList,
  MenuTrigger,
} from '@/flavours/glitch/components/menu';
import { FOCUS_TARGET } from '@/flavours/glitch/components/navigation_focus_target';
import { openNewComposer } from '@/flavours/glitch/reducers/slices/composer';
import {
  SHARLAYAN_MINI_NAVIGATION_KEYS,
  useSharlayanAntennaLinks,
  useSharlayanExtensionLinks,
  useSharlayanPrimaryNavigationLinks,
} from '@/flavours/glitch/sharlayan/registry/navigation/redesign';
import { useAppDispatch } from '@/flavours/glitch/store';

import { handleSearchLinkClick } from '.';
import classes from './collapsed.module.scss';
import { useCustomFeeds, useFollowedHashtags } from './hooks';
import {
  MiniAccountLink,
  MiniHomeLink,
  MiniMessagesLink,
  MiniNotificationsLink,
} from './mini_nav';
import type { MiniNavigationLinkProps } from './navigation_link';
import { MiniNavigationLink } from './navigation_link';

const messages = defineMessages({
  main: {
    id: 'navigation_bar.main',
    defaultMessage: 'Main',
    description:
      'Label for the main navigation; should not contain the word "navigation".',
  },
});

const MAX_MENU_ITEM_COUNT = 10;

export const CollapsedNavigationPanel: React.FC<{
  multiColumn?: boolean;
  onToggleCollapsed?: () => void;
}> = ({ multiColumn, onToggleCollapsed }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { customFeeds } = useCustomFeeds();
  const { followedHashtags } = useFollowedHashtags();

  const primaryLinks = useSharlayanPrimaryNavigationLinks({
    omit: SHARLAYAN_MINI_NAVIGATION_KEYS,
  });
  const extensionLinks = useSharlayanExtensionLinks();
  const antennaLinks = useSharlayanAntennaLinks();

  const openComposer = useCallback(() => {
    dispatch(openNewComposer({ type: 'post' }));
  }, [dispatch]);

  const tooltipPlacement = 'right';

  return (
    <nav
      className={classes.root}
      aria-label={intl.formatMessage(messages.main)}
    >
      <IconButton
        icon={multiColumn ? CaretLineRightIcon : CaretLineLeftIcon}
        size='sm'
        tooltipPlacement={tooltipPlacement}
        onClick={onToggleCollapsed}
        className={classNames(classes.expandButton, 'rtl-flip')}
      >
        <FormattedMessage
          id='navigation_bar.expand'
          defaultMessage='Expand Menu'
        />
      </IconButton>
      <ul className={classes.list}>
        <li>
          <MiniHomeLink tooltipPlacement={tooltipPlacement} />
        </li>
        <li>
          <MiniNavigationLink
            to={{
              pathname: '/search',
              state: { focusTarget: FOCUS_TARGET.SEARCH },
            }}
            onClick={handleSearchLinkClick}
            icon={MagnifyingGlassIcon}
            tooltipPlacement={tooltipPlacement}
          >
            <FormattedMessage id='tabs_bar.search' defaultMessage='Search' />
          </MiniNavigationLink>
        </li>
        <li>
          <MiniMessagesLink tooltipPlacement={tooltipPlacement} />
        </li>
        <li>
          <MiniNotificationsLink
            tooltipPlacement={tooltipPlacement}
            badgeType='dot'
          />
        </li>
        <li className={classes.itemWithBottomBorder}>
          <MiniAccountLink
            tooltipPlacement={tooltipPlacement}
            menuPlacement='right-start'
          />
        </li>

        <li className={classes.itemWithBottomBorder}>
          <IconButton
            icon={PenNibIcon}
            onClick={openComposer}
            variant='solid'
            color='accent'
            size='md'
            tooltipPlacement={tooltipPlacement}
          >
            <FormattedMessage id='tabs_bar.publish' defaultMessage='New Post' />
          </IconButton>
        </li>

        {primaryLinks.map((link, index) => (
          <li
            key={link.key}
            className={
              index === primaryLinks.length - 1
                ? classes.itemWithBottomBorder
                : undefined
            }
          >
            <MiniNavigationLink
              to={link.to ?? '/'}
              exact={link.exact}
              icon={link.icon}
              badgeCount={link.badgeCount}
              badgeType='dot'
              tooltipPlacement={tooltipPlacement}
            >
              {link.label}
            </MiniNavigationLink>
          </li>
        ))}

        <li>
          <MenuSection
            icon={PuzzlePieceIcon}
            title={
              <FormattedMessage
                id='navigation_bar.extensions'
                defaultMessage='Extensions'
              />
            }
          >
            {extensionLinks.map((link) =>
              link.to ? (
                <MenuItemLink key={link.key} to={link.to} icon={link.icon}>
                  {link.label}
                </MenuItemLink>
              ) : (
                <MenuItem
                  key={link.key}
                  onClick={link.onClick}
                  icon={link.icon}
                >
                  {link.label}
                </MenuItem>
              ),
            )}
          </MenuSection>
        </li>

        <li>
          <MenuSection
            icon={RssSimpleIcon}
            title={
              <FormattedMessage
                id='tabs_bar.custom_feeds'
                defaultMessage='Custom Feeds'
              />
            }
          >
            <MenuItemLink to='/lists/new' icon={PlusIcon}>
              <FormattedMessage
                id='tabs_bar.create_custom_feed'
                defaultMessage='Create Feed'
              />
            </MenuItemLink>

            {customFeeds.slice(0, MAX_MENU_ITEM_COUNT).map((feed) => (
              <MenuItemLink
                key={feed.id}
                to={`/lists/${feed.id}`}
                icon={RssSimpleIcon}
              >
                {feed.title}
              </MenuItemLink>
            ))}

            {customFeeds.length > MAX_MENU_ITEM_COUNT && (
              <MenuItemLink key='view-all' to='/lists' icon={ArrowUpRightIcon}>
                <FormattedMessage
                  id='tabs_bar.followed_tags_view_all'
                  defaultMessage='View all'
                />
              </MenuItemLink>
            )}
          </MenuSection>
        </li>

        {antennaLinks.length > 0 && (
          <li>
            <MenuSection
              icon={RssSimpleIcon}
              title={
                <FormattedMessage
                  id='navigation_bar.antennas'
                  defaultMessage='Antennas'
                />
              }
            >
              <MenuItemLink to='/antennas' icon={ArrowUpRightIcon}>
                <FormattedMessage
                  id='tabs_bar.followed_tags_view_all'
                  defaultMessage='View all'
                />
              </MenuItemLink>
              {antennaLinks.map((link) => (
                <MenuItemLink
                  key={link.key}
                  to={link.to ?? '/antennas'}
                  icon={link.icon}
                >
                  {link.label}
                </MenuItemLink>
              ))}
            </MenuSection>
          </li>
        )}

        {followedHashtags.length > 0 && (
          <li>
            <MenuSection
              icon={HashIcon}
              title={
                <FormattedMessage
                  id='tabs_bar.followed_hashtags'
                  defaultMessage='Followed Hashtags'
                />
              }
            >
              {followedHashtags.slice(0, MAX_MENU_ITEM_COUNT).map((tag) => (
                <MenuItemLink key={tag.name} to={`/tags/${tag.name}`}>
                  #{tag.name}
                </MenuItemLink>
              ))}

              {followedHashtags.length > MAX_MENU_ITEM_COUNT && (
                <MenuItemLink
                  key='view-all'
                  to='/lists'
                  icon={ArrowUpRightIcon}
                >
                  <FormattedMessage
                    id='tabs_bar.followed_tags_view_all'
                    defaultMessage='View all'
                  />
                </MenuItemLink>
              )}
            </MenuSection>
          </li>
        )}
      </ul>
    </nav>
  );
};

const MenuSection: React.FC<{
  title: React.ReactNode;
  icon: MiniNavigationLinkProps['icon'];
  children: React.ReactNode;
}> = ({ title, icon, children }) => {
  return (
    <Menu type='navigation'>
      <MenuTrigger as={MiniNavigationLinkAsMenuButton} icon={icon}>
        {title}
      </MenuTrigger>
      <MenuList placement='right'>
        <MenuItemGroup label={title}>{children}</MenuItemGroup>
      </MenuList>
    </Menu>
  );
};

interface AccountButton
  extends
    React.ComponentPropsWithRef<'button'>,
    Pick<MiniNavigationLinkProps, 'icon'> {}

export const MiniNavigationLinkAsMenuButton: React.FC<AccountButton> = ({
  children,
  ...otherProps
}) => {
  return (
    <MiniNavigationLink
      as='button'
      withMenuIndicator
      tooltipPlacement='right'
      {...otherProps}
    >
      {children}
    </MiniNavigationLink>
  );
};
