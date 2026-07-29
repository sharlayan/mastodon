import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import type { ApiPageSeriesJSON } from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';

export const BookletListItem: React.FC<{
  booklet: ApiPageSeriesJSON;
  owned?: boolean;
}> = ({ booklet, owned = false }) => {
  const href = booklet.main_page_name
    ? `/@${booklet.account.acct}/pages/${encodeURIComponent(booklet.main_page_name)}`
    : owned
      ? `/pages/booklets/${booklet.id}/edit`
      : `/@${booklet.account.acct}/pages`;

  return (
    <article className='booklet-list-item'>
      <Link to={href} className='booklet-list-item__link'>
        {booklet.cover_media_attachment ? (
          <img
            className='booklet-list-item__cover'
            src={booklet.cover_media_attachment.url}
            alt=''
            loading='lazy'
            decoding='async'
          />
        ) : (
          <span className='booklet-list-item__cover booklet-list-item__cover--empty' />
        )}
        <span className='booklet-list-item__details'>
          <strong>[{booklet.title}]</strong>
          {booklet.description && <span>{booklet.description}</span>}
          <span className='booklet-list-item__author'>
            <Avatar account={booklet.account} size={24} />
            {booklet.account.display_name || booklet.account.username} · @
            {booklet.account.acct}
          </span>
          <span>
            <FormattedMessage
              id='pages.booklet.pages_count'
              defaultMessage='{count, plural, one {# page} other {# pages}}'
              values={{ count: booklet.pages_count }}
            />
          </span>
        </span>
      </Link>
    </article>
  );
};
