import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';

const messages = defineMessages({
  seriesMain: {
    id: 'pages.series.main',
    defaultMessage: 'Representative page',
  },
});

export const PageSeries: React.FC<{
  page: ApiPageJSON;
}> = ({ page }) => {
  const intl = useIntl();

  if (!page.booklet) {
    return null;
  }

  return (
    <aside
      className={classNames('page__series', {
        'page__series--with-cover': page.booklet.cover_media_attachment,
      })}
    >
      {page.booklet.cover_media_attachment && (
        <img
          className='page__series-cover'
          src={page.booklet.cover_media_attachment.url}
          alt=''
          decoding='async'
          loading='lazy'
        />
      )}
      <div className='page__series-details'>
        <strong>
          [{page.booklet.title}]
          {page.booklet_main && (
            <span className='page__series-main'>
              {intl.formatMessage(messages.seriesMain)}
            </span>
          )}
        </strong>
        {page.booklet.description && <p>{page.booklet.description}</p>}
      </div>
    </aside>
  );
};
