import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';
import { Link, useLocation } from 'react-router-dom';

import FavoriteIcon from '@/material-icons/400-24px/favorite-fill.svg?react';
import FavoriteBorderIcon from '@/material-icons/400-24px/favorite.svg?react';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { FormattedDateWrapper } from 'flavours/glitch/components/formatted_date';
import { Icon } from 'flavours/glitch/components/icon';

const messages = defineMessages({
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
  const location = useLocation();

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
              to={{
                pathname: `/@${previousPage.account.acct}/pages/${encodeURIComponent(previousPage.name)}`,
                state: location.state,
              }}
            >
              <span className='page__pagination-label'>
                <FormattedMessage
                  id='pages.previous'
                  defaultMessage='Previous page'
                />
              </span>
              <span className='page__pagination-title'>
                {previousPage.title || previousPage.name}
              </span>
            </Link>
          ) : (
            <span />
          )}
          {nextPage && (
            <Link
              className='page__link-next'
              to={{
                pathname: `/@${nextPage.account.acct}/pages/${encodeURIComponent(nextPage.name)}`,
                state: location.state,
              }}
            >
              <span className='page__pagination-label'>
                <FormattedMessage id='pages.next' defaultMessage='Next page' />
              </span>
              <span className='page__pagination-title'>
                {nextPage.title || nextPage.name}
              </span>
            </Link>
          )}
        </nav>
      )}
    </>
  );
};
