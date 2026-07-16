import { FormattedMessage } from 'react-intl';

import classNames from 'classnames';
import { Link } from 'react-router-dom';

import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';

export const PageListItem: React.FC<{ page: ApiPageJSON }> = ({ page }) => {
  const headerUrl = page.eye_catching_media_attachment?.url;

  return (
    <div
      className={classNames('lists__item', 'page-list-item', {
        'page-list-item--with-header': headerUrl,
      })}
      style={
        headerUrl
          ? { backgroundImage: `url(${JSON.stringify(headerUrl)})` }
          : undefined
      }
    >
      <Link to={`/pages/${page.id}`} className='lists__item__title'>
        <span className='page-list-item__details'>
          <Avatar account={page.account} size={32} />
          <span className='page-list-item__text'>
            <span className='page-list-item__title'>
              {page.title || page.name}
            </span>
            <span className='page-list-item__author'>
              {page.account.display_name || page.account.username} · @
              {page.account.acct}
              {page.category && <> · {page.category}</>}
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
