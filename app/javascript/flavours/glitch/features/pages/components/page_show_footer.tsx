import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link } from 'react-router-dom';

import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import FavoriteIcon from '@/material-icons/400-24px/favorite-fill.svg?react';
import FavoriteBorderIcon from '@/material-icons/400-24px/favorite.svg?react';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { FormattedDateWrapper } from 'flavours/glitch/components/formatted_date';
import { Icon } from 'flavours/glitch/components/icon';

const messages = defineMessages({
  edit: { id: 'pages.edit', defaultMessage: 'Edit page' },
  createdAt: { id: 'pages.created_at', defaultMessage: 'Created' },
  updatedAt: { id: 'pages.updated_at', defaultMessage: 'Updated' },
});

export const PageShowFooter: React.FC<{
  page: ApiPageJSON;
  isOwner: boolean;
  isBlogView: boolean;
  previousPage: ApiPageJSON | null;
  nextPage: ApiPageJSON | null;
  onLikeToggle: () => void;
}> = ({ page, isOwner, isBlogView, previousPage, nextPage, onLikeToggle }) => {
  const intl = useIntl();

  return (
    <>
      <div className='page__footer'>
        <dl className='page__dates'>
          <div>
            <dt>{intl.formatMessage(messages.createdAt)}</dt>
            <dd>
              <FormattedDateWrapper
                value={page.created_at}
                year='numeric'
                month='long'
                day='2-digit'
                hour='2-digit'
                minute='2-digit'
              />
            </dd>
          </div>
          <div>
            <dt>{intl.formatMessage(messages.updatedAt)}</dt>
            <dd>
              <FormattedDateWrapper
                value={page.updated_at}
                year='numeric'
                month='long'
                day='2-digit'
                hour='2-digit'
                minute='2-digit'
              />
            </dd>
          </div>
        </dl>
        <div className='page__footer-actions'>
          {isBlogView && isOwner && (
            <Link
              to={{
                pathname: `/pages/${page.id}/edit`,
                state: { fromPageShow: true, pageName: page.name },
              }}
              className='page__like-button'
              title={intl.formatMessage(messages.edit)}
              aria-label={intl.formatMessage(messages.edit)}
            >
              <Icon id='pencil' icon={EditIcon} />
            </Link>
          )}
          <button
            type='button'
            className={classNames('page__like-button', { active: page.liked })}
            onClick={onLikeToggle}
            disabled={isOwner}
          >
            <Icon
              id='favorite'
              icon={page.liked ? FavoriteIcon : FavoriteBorderIcon}
            />
            <span>
              <FormattedMessage
                id='pages.likes_count'
                defaultMessage='{count, plural, one {# like} other {# likes}}'
                values={{ count: page.likes_count }}
              />
            </span>
          </button>
        </div>
      </div>
      {isBlogView && Boolean(previousPage ?? nextPage) && (
        <nav
          className='page__pagination'
          aria-label={intl.formatMessage({
            id: 'pages.pagination',
            defaultMessage: 'Page navigation',
          })}
        >
          {previousPage ? (
            <Link
              className='page__link-prev'
              to={`/@${previousPage.account.acct}/pages/${encodeURIComponent(previousPage.name)}`}
            >
              <FormattedMessage
                id='pages.previous'
                defaultMessage='Previous page'
              />
            </Link>
          ) : (
            <span />
          )}
          {nextPage && (
            <Link
              className='page__link-next'
              to={`/@${nextPage.account.acct}/pages/${encodeURIComponent(nextPage.name)}`}
            >
              <FormattedMessage id='pages.next' defaultMessage='Next page' />
            </Link>
          )}
        </nav>
      )}
    </>
  );
};
