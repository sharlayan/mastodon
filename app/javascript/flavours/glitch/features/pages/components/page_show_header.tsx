import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link } from 'react-router-dom';

import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import FlagIcon from '@/material-icons/400-24px/flag.svg?react';
import FullscreenIcon from '@/material-icons/400-24px/fullscreen.svg?react';
import FullscreenExitIcon from '@/material-icons/400-24px/fullscreen_exit.svg?react';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { Icon } from 'flavours/glitch/components/icon';

const messages = defineMessages({
  edit: { id: 'pages.edit', defaultMessage: 'Edit page' },
  delete: { id: 'pages.delete', defaultMessage: 'Delete page' },
  report: { id: 'pages.report', defaultMessage: 'Report page' },
  wideView: { id: 'pages.wide_view', defaultMessage: 'Wide view' },
  exitWideView: {
    id: 'pages.exit_wide_view',
    defaultMessage: 'Exit wide view',
  },
});

export const PageShowHeader: React.FC<{
  page: ApiPageJSON;
  accountId: string | undefined;
  isOwner: boolean;
  isBlogView: boolean;
  isWideView: boolean;
  multiColumn?: boolean;
  onBack: () => void;
  onDelete: () => void;
  onReport: () => void;
  onWideViewToggle: () => void;
}> = ({
  page,
  accountId,
  isOwner,
  isBlogView,
  isWideView,
  multiColumn,
  onBack,
  onDelete,
  onReport,
  onWideViewToggle,
}) => {
  const intl = useIntl();
  const ownerName = page.account.display_name || page.account.username;

  if (isBlogView) {
    return (
      <header className='page-show__blog-header'>
        <Link
          to={`/@${page.account.acct}`}
          className='page-show__blog-owner'
          style={
            page.account.header
              ? ({
                  '--page-blog-owner-header': `url(${JSON.stringify(page.account.header)})`,
                } as React.CSSProperties)
              : undefined
          }
        >
          <Avatar account={page.account} size={40} />
          <span className='page-show__blog-owner-text'>
            <strong>{ownerName}</strong>
            <span>@{page.account.acct}</span>
          </span>
        </Link>
        {accountId && (
          <nav
            className='page-show__blog-navigation'
            aria-label={intl.formatMessage({
              id: 'pages.blog_header.navigation',
              defaultMessage: 'Page links',
            })}
          >
            <Link to='/home'>
              <FormattedMessage
                id='pages.blog_header.home'
                defaultMessage='Back to home timeline'
              />
            </Link>
            <span aria-hidden='true'>|</span>
            <Link to='/pages'>
              <FormattedMessage
                id='pages.blog_header.my_pages'
                defaultMessage='Back to my pages'
              />
            </Link>
            <span aria-hidden='true'>|</span>
            <Link to={`/@${page.account.acct}`}>
              <FormattedMessage
                id='pages.blog_header.owner_profile'
                defaultMessage="Back to {user}'s profile"
                values={{ user: ownerName }}
              />
            </Link>
          </nav>
        )}
      </header>
    );
  }

  return (
    <ColumnHeader
      title={page.title}
      icon='description'
      iconComponent={DescriptionIcon}
      multiColumn={multiColumn}
      showBackButton
      onBack={onBack}
      extraButton={
        <>
          {isOwner && (
            <>
              <Link
                to={{
                  pathname: `/pages/${page.id}/edit`,
                  state: { fromPageShow: true, pageName: page.name },
                }}
                className='column-header__button'
                title={intl.formatMessage(messages.edit)}
                aria-label={intl.formatMessage(messages.edit)}
              >
                <Icon id='pencil' icon={EditIcon} />
              </Link>
              <button
                type='button'
                className='column-header__button'
                title={intl.formatMessage(messages.delete)}
                aria-label={intl.formatMessage(messages.delete)}
                onClick={onDelete}
              >
                <Icon id='trash' icon={DeleteIcon} />
              </button>
            </>
          )}
          {accountId && !isOwner && !page.locked && (
            <button
              type='button'
              className='column-header__button'
              title={intl.formatMessage(messages.report)}
              aria-label={intl.formatMessage(messages.report)}
              onClick={onReport}
            >
              <Icon id='flag' icon={FlagIcon} />
            </button>
          )}
          <button
            type='button'
            className='column-header__button'
            title={intl.formatMessage(
              isWideView ? messages.exitWideView : messages.wideView,
            )}
            aria-label={intl.formatMessage(
              isWideView ? messages.exitWideView : messages.wideView,
            )}
            aria-pressed={isWideView}
            onClick={onWideViewToggle}
          >
            <Icon
              id={isWideView ? 'compress' : 'expand'}
              icon={isWideView ? FullscreenExitIcon : FullscreenIcon}
            />
          </button>
        </>
      }
    />
  );
};
