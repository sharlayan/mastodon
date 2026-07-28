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
import { isServerPageBlogViewPath } from 'flavours/glitch/initial_state';

import { CategoryFilter } from './components/category_filter';
import { PageListItem } from './components/page_list_item';

const messages = defineMessages({
  heading: { id: 'column.pages', defaultMessage: 'Pages' },
  create: { id: 'pages.create', defaultMessage: 'Create page' },
});

const Pages: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { signedIn } = useIdentity();
  const [tab, setTab] = useState<'mine' | 'featured'>('mine');
  const [pages, setPages] = useState<ApiPageJSON[]>([]);
  const [category, setCategory] = useState('');
  const useBlogView = isServerPageBlogViewPath(window.location.pathname);

  useEffect(() => {
    document.documentElement.classList.toggle('page-blog-view', useBlogView);
    document.body.classList.toggle('page-blog-view', useBlogView);

    return () => {
      document.documentElement.classList.remove('page-blog-view');
      document.body.classList.remove('page-blog-view');
    };
  }, [useBlogView]);

  useEffect(() => {
    if (!signedIn) {
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
      setCategory('');
    },
    [],
  );

  const emptyMessage = (
    <FormattedMessage id='pages.no_pages_yet' defaultMessage='No pages yet.' />
  );
  const visiblePages = category
    ? pages.filter((page) => page.category === category)
    : pages;

  return (
    <Column
      bindToDocument={!multiColumn}
      className='page-index-column'
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

      {tab === 'mine' && (
        <CategoryFilter pages={pages} value={category} onChange={setCategory} />
      )}

      <ScrollableList
        scrollKey='pages'
        emptyMessage={emptyMessage}
        bindToDocument={!multiColumn}
      >
        {!signedIn ? (
          <NotSignedInIndicator />
        ) : (
          visiblePages.map((page) => (
            <PageListItem
              key={page.id}
              page={page}
              showCategory={tab !== 'featured'}
            />
          ))
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
