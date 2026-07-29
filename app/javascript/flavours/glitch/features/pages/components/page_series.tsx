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

  if (!page.page_series) {
    return null;
  }

  return (
    <aside
      className={classNames('page__series', {
        'page__series--main': page.series_main,
      })}
    >
      {page.series_main && page.page_series.cover_media_attachment && (
        <img
          className='page__series-cover'
          src={page.page_series.cover_media_attachment.url}
          alt=''
          decoding='async'
          loading='lazy'
        />
      )}
      <div className='page__series-details'>
        <strong>
          [{page.page_series.title}]
          {page.series_main && (
            <span className='page__series-main'>
              {intl.formatMessage(messages.seriesMain)}
            </span>
          )}
        </strong>
        {page.page_series.description && <p>{page.page_series.description}</p>}
      </div>
    </aside>
  );
};
