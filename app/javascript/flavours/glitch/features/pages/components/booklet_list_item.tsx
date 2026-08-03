import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link } from 'react-router-dom';

import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import VisibilityIcon from '@/material-icons/400-24px/visibility.svg?react';
import type { ApiPageSeriesJSON } from 'flavours/glitch/api_types/pages';
import { Avatar } from 'flavours/glitch/components/avatar';
import { Icon } from 'flavours/glitch/components/icon';

const messages = defineMessages({
  view: {
    id: 'pages.booklet.view',
    defaultMessage: 'View Booklet',
  },
  edit: {
    id: 'pages.booklet.edit',
    defaultMessage: 'Edit Booklet',
  },
});

export const BookletListItem: React.FC<{
  booklet: ApiPageSeriesJSON;
  owned?: boolean;
}> = ({ booklet, owned = false }) => {
  const intl = useIntl();
  const href = booklet.entry_page_name
    ? `/@${booklet.account.acct}/pages/${encodeURIComponent(booklet.entry_page_name)}`
    : `/@${booklet.account.acct}/pages`;

  return (
    <article className='booklet-list-item'>
      {!owned && (
        <Link
          to={href}
          className='booklet-list-item__view-link'
          aria-label={`${intl.formatMessage(messages.view)}: ${booklet.title}`}
        />
      )}
      <div className='booklet-list-item__content'>
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
          <span>
            <FormattedMessage
              id='pages.booklet.pages_count'
              defaultMessage='{count, plural, one {# page} other {# pages}}'
              values={{ count: booklet.pages_count }}
            />
          </span>
          <span className='booklet-list-item__author'>
            <span className='booklet-list-item__owner'>
              <Avatar account={booklet.account} size={24} />
              {booklet.account.display_name || booklet.account.username} · @
              {booklet.account.acct}
            </span>
            {owned && (
              <span className='booklet-list-item__actions'>
                <Link
                  to={href}
                  title={intl.formatMessage(messages.view)}
                  aria-label={intl.formatMessage(messages.view)}
                >
                  <Icon id='visibility' icon={VisibilityIcon} />
                </Link>
                <Link
                  to={`/pages/booklets/${booklet.id}/edit`}
                  title={intl.formatMessage(messages.edit)}
                  aria-label={intl.formatMessage(messages.edit)}
                >
                  <Icon id='pencil' icon={EditIcon} />
                </Link>
              </span>
            )}
          </span>
        </span>
      </div>
    </article>
  );
};
