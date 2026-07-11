import { useEffect, useState, useCallback } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import { NotSignedInIndicator } from '@/flavours/glitch/components/not_signed_in_indicator';
import { useIdentity } from '@/flavours/glitch/identity_context';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import { apiGetPages, apiGetFeaturedPages } from 'flavours/glitch/api/pages';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { Icon } from 'flavours/glitch/components/icon';
import ScrollableList from 'flavours/glitch/components/scrollable_list';

const messages = defineMessages({
  heading: { id: 'column.pages', defaultMessage: 'Pages' },
  create: { id: 'pages.create', defaultMessage: 'Create page' },
});

export const PageListItem: React.FC<{ page: ApiPageJSON }> = ({ page }) => (
  <div className='lists__item'>
    <Link to={`/pages/${page.id}`} className='lists__item__title'>
      <Icon id='description' icon={DescriptionIcon} />
      <span>{page.title || page.name}</span>
      <span className='lists__item__count'>
        <FormattedMessage
          id='pages.likes_count'
          defaultMessage='{count, plural, one {# like} other {# likes}}'
          values={{ count: page.likes_count }}
        />
      </span>
    </Link>
  </div>
);

const Pages: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { signedIn } = useIdentity();
  const [tab, setTab] = useState<'mine' | 'featured'>('mine');
  const [pages, setPages] = useState<ApiPageJSON[]>([]);

  useEffect(() => {
    if (!signedIn && tab === 'mine') {
      return;
    }

    const request = tab === 'featured' ? apiGetFeaturedPages() : apiGetPages();

    request
      .then((data) => {
        setPages(data);
        return data;
      })
      .catch(() => undefined);
  }, [signedIn, tab]);

  const handleTabClick = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      setTab(event.currentTarget.dataset.tab as 'mine' | 'featured');
    },
    [],
  );

  const emptyMessage = (
    <FormattedMessage id='pages.no_pages_yet' defaultMessage='No pages yet.' />
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        title={intl.formatMessage(messages.heading)}
        icon='description'
        iconComponent={DescriptionIcon}
        multiColumn={multiColumn}
        extraButton={
          signedIn && (
            <Link
              to='/pages/new'
              className='column-header__button'
              title={intl.formatMessage(messages.create)}
              aria-label={intl.formatMessage(messages.create)}
            >
              <Icon id='plus' icon={AddIcon} />
            </Link>
          )
        }
      />

      <div className='account__section-headline'>
        <button
          type='button'
          className={tab === 'mine' ? 'active' : undefined}
          data-tab='mine'
          onClick={handleTabClick}
        >
          <FormattedMessage id='pages.tab.mine' defaultMessage='My pages' />
        </button>
        <button
          type='button'
          className={tab === 'featured' ? 'active' : undefined}
          data-tab='featured'
          onClick={handleTabClick}
        >
          <FormattedMessage id='pages.tab.featured' defaultMessage='Featured' />
        </button>
      </div>

      <ScrollableList
        scrollKey='pages'
        emptyMessage={emptyMessage}
        bindToDocument={!multiColumn}
      >
        {tab === 'mine' && !signedIn ? (
          <NotSignedInIndicator />
        ) : (
          pages.map((page) => <PageListItem key={page.id} page={page} />)
        )}
      </ScrollableList>

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default Pages;
