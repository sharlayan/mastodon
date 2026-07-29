import { useCallback, useEffect, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import { NotSignedInIndicator } from '@/flavours/glitch/components/not_signed_in_indicator';
import { useIdentity } from '@/flavours/glitch/identity_context';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import {
  apiGetFeaturedPages,
  apiGetOtherPageSeries,
  apiGetPages,
  apiGetPageSeries,
  PAGE_LIST_LIMIT,
} from 'flavours/glitch/api/pages';
import type {
  ApiPageJSON,
  ApiPageSeriesJSON,
} from 'flavours/glitch/api_types/pages';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { Icon } from 'flavours/glitch/components/icon';
import ScrollableList from 'flavours/glitch/components/scrollable_list';

import { BookletListItem } from './components/booklet_list_item';
import { PageListItem } from './components/page_list_item';

type PagesTab = 'mine' | 'my-booklets' | 'other-booklets' | 'featured';

const messages = defineMessages({
  heading: { id: 'column.pages', defaultMessage: 'Pages' },
  createPage: { id: 'pages.create', defaultMessage: 'Create page' },
  createBooklet: {
    id: 'pages.booklet.new',
    defaultMessage: 'Create Booklet',
  },
});

const Pages: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { signedIn } = useIdentity();
  const [tab, setTab] = useState<PagesTab>('mine');
  const [pages, setPages] = useState<ApiPageJSON[]>([]);
  const [booklets, setBooklets] = useState<ApiPageSeriesJSON[]>([]);
  const [loadedTab, setLoadedTab] = useState<PagesTab | null>(null);
  const [loading, setLoading] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const requestGeneration = useRef(0);

  useEffect(() => {
    const generation = ++requestGeneration.current;
    if (!signedIn) return;
    const request =
      tab === 'mine'
        ? apiGetPages()
        : tab === 'featured'
          ? apiGetFeaturedPages()
          : tab === 'my-booklets'
            ? apiGetPageSeries()
            : apiGetOtherPageSeries();

    void request
      .then((data) => {
        if (requestGeneration.current !== generation) return;
        if (tab === 'mine' || tab === 'featured') {
          setPages(data as ApiPageJSON[]);
          setBooklets([]);
          setHasMore(tab === 'mine' && data.length === PAGE_LIST_LIMIT);
        } else {
          setBooklets(data as ApiPageSeriesJSON[]);
          setPages([]);
          setHasMore(false);
        }
        setLoadedTab(tab);
        setLoading(false);
      })
      .catch(() => {
        if (requestGeneration.current !== generation) return;
        setPages([]);
        setBooklets([]);
        setHasMore(false);
        setLoadedTab(tab);
        setLoading(false);
      });
  }, [signedIn, tab]);

  const handleLoadMore = useCallback(() => {
    if (!signedIn || loading || !hasMore || tab !== 'mine') return;
    const generation = requestGeneration.current;
    setLoading(true);
    void apiGetPages(pages.length)
      .then((data) => {
        if (requestGeneration.current !== generation) return;
        setPages((current) => [...current, ...data]);
        setHasMore(data.length === PAGE_LIST_LIMIT);
        setLoading(false);
      })
      .catch(() => {
        setLoading(false);
      });
  }, [hasMore, loading, pages.length, signedIn, tab]);

  const showMine = useCallback(() => {
    setTab('mine');
  }, []);
  const showMyBooklets = useCallback(() => {
    setTab('my-booklets');
  }, []);
  const showOtherBooklets = useCallback(() => {
    setTab('other-booklets');
  }, []);
  const showFeatured = useCallback(() => {
    setTab('featured');
  }, []);

  const createBooklet = tab === 'my-booklets';
  const initialLoading = signedIn && loadedTab !== tab;

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
              to={createBooklet ? '/pages/booklets/new' : '/pages/new'}
              className='column-header__button'
              title={intl.formatMessage(
                createBooklet ? messages.createBooklet : messages.createPage,
              )}
              aria-label={intl.formatMessage(
                createBooklet ? messages.createBooklet : messages.createPage,
              )}
            >
              <Icon id='plus' icon={AddIcon} />
            </Link>
          )
        }
      />
      <div className='account__section-headline page-index__tabs'>
        <button
          type='button'
          className={tab === 'mine' ? 'active' : undefined}
          onClick={showMine}
        >
          <FormattedMessage id='pages.tab.mine' defaultMessage='My pages' />
        </button>
        <button
          type='button'
          className={tab === 'my-booklets' ? 'active' : undefined}
          onClick={showMyBooklets}
        >
          <FormattedMessage
            id='pages.tab.my_booklets'
            defaultMessage='My Booklets'
          />
        </button>
        <button
          type='button'
          className={tab === 'other-booklets' ? 'active' : undefined}
          onClick={showOtherBooklets}
        >
          <FormattedMessage
            id='pages.tab.other_booklets'
            defaultMessage="Other people's Booklets"
          />
        </button>
        <button
          type='button'
          className={tab === 'featured' ? 'active' : undefined}
          onClick={showFeatured}
        >
          <FormattedMessage
            id='pages.tab.featured'
            defaultMessage='Featured pages'
          />
        </button>
      </div>
      <ScrollableList
        scrollKey={`pages-${tab}`}
        onLoadMore={handleLoadMore}
        hasMore={loadedTab === tab && hasMore}
        isLoading={loading || initialLoading}
        showLoading={initialLoading}
        emptyMessage={
          tab.includes('booklets') ? (
            <FormattedMessage
              id='pages.booklet.none_yet'
              defaultMessage='No Booklets yet.'
            />
          ) : (
            <FormattedMessage
              id='pages.no_pages_yet'
              defaultMessage='No pages yet.'
            />
          )
        }
        bindToDocument={!multiColumn}
      >
        {!signedIn ? (
          <NotSignedInIndicator />
        ) : tab === 'mine' || tab === 'featured' ? (
          pages.map((page) => <PageListItem key={page.id} page={page} />)
        ) : (
          booklets.map((booklet) => (
            <BookletListItem
              key={booklet.id}
              booklet={booklet}
              owned={tab === 'my-booklets'}
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

export default Pages;
