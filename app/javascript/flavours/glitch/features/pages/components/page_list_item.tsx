import { FormattedMessage } from 'react-intl';

import classNames from 'classnames';
import { Link, useLocation } from 'react-router-dom';

import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';

export const PageListItem: React.FC<{
  page: ApiPageJSON;
  showCategory?: boolean;
  active?: boolean;
  replaceHistory?: boolean;
}> = ({
  page,
  showCategory = true,
  active = false,
  replaceHistory = false,
}) => {
  const location = useLocation();
  const headerUrl = page.eye_catching_media_attachment?.url;
  const pathname = `/pages/${page.id}`;

  return (
    <div
      className={classNames('lists__item', 'page-list-item', {
        'page-list-item--with-header': headerUrl,
        'page-list-item--active': active,
      })}
      style={
        headerUrl
          ? { backgroundImage: `url(${JSON.stringify(headerUrl)})` }
          : undefined
      }
    >
      <Link
        to={replaceHistory ? { pathname, state: location.state } : pathname}
        className='lists__item__title'
        aria-current={active ? 'page' : undefined}
        replace={replaceHistory}
      >
        <span className='page-list-item__details'>
          <Avatar account={page.account} size={32} />
          <span className='page-list-item__text'>
            <span className='page-list-item__title'>
              {page.title || page.name}
              {showCategory && page.category && (
                <>
                  {' · '}
                  <span className='page-list-item__category'>
                    {page.category}
                  </span>
                </>
              )}
            </span>
            <span className='page-list-item__author'>
              {page.account.display_name || page.account.username} · @
              {page.account.acct}
            </span>
          </span>
          <span className='page-list-item__aside'>
            {page.draft && (
              <span className='page-list-item__draft'>
                <FormattedMessage id='pages.draft' defaultMessage='Draft' />
              </span>
            )}
            <span className='lists__item__count'>
              <FormattedMessage
                id='pages.likes_count'
                defaultMessage='{count, plural, one {# like} other {# likes}}'
                values={{ count: page.likes_count }}
              />
            </span>
          </span>
        </span>
      </Link>
    </div>
  );
};
