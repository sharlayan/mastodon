import { useCallback, useEffect, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Link } from 'react-router-dom';

import type { Map as ImmutableMap } from 'immutable';

import { Helmet } from '@unhead/react/helmet';

import { NotSignedInIndicator } from '@/flavours/glitch/components/not_signed_in_indicator';
import { useIdentity } from '@/flavours/glitch/identity_context';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import { changeLocalSetting } from 'flavours/glitch/actions/local_settings';
import {
  apiGetFeaturedPages,
  apiGetOtherPageSeries,
  apiGetPages,
  apiGetPageSeries,
  apiGetPageWritingStatistics,
  PAGE_LIST_LIMIT,
} from 'flavours/glitch/api/pages';
import type {
  ApiPageJSON,
  ApiPageSeriesJSON,
  ApiPageWritingStatisticsJSON,
} from 'flavours/glitch/api_types/pages';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { Icon } from 'flavours/glitch/components/icon';
import ScrollableList from 'flavours/glitch/components/scrollable_list';
import SettingToggle from 'flavours/glitch/features/notifications/components/setting_toggle';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { BookletListItem } from './components/booklet_list_item';
import { PageListItem } from './components/page_list_item';
import { WritingStatistics } from './components/writing_statistics';

type Bookcase = 'mine' | 'public';
type Shelf = 'pages' | 'booklets';

const messages = defineMessages({
  heading: { id: 'column.pages', defaultMessage: 'Pages' },
  createPage: { id: 'pages.create', defaultMessage: 'Create page' },
  createBooklet: {
    id: 'pages.booklet.new',
    defaultMessage: 'Create Booklet',
  },
  showActivity: {
    id: 'pages.statistics.show_activity',
    defaultMessage: 'Show activity',
  },
  showReport: {
    id: 'pages.statistics.show_report',
    defaultMessage: 'Show writing report',
  },
});

export const Pages: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { signedIn } = useIdentity();
  const pageSettings = useAppSelector(
    (state) =>
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access
      state.local_settings.get('pages') as ImmutableMap<string, boolean>,
  );
  const showWritingStatistics = pageSettings.get('show_activity', true);
  const showWritingReport = pageSettings.get('show_report', true);
  const [bookcase, setBookcase] = useState<Bookcase>('mine');
  const [shelf, setShelf] = useState<Shelf>('pages');
  const [pages, setPages] = useState<ApiPageJSON[]>([]);
  const [booklets, setBooklets] = useState<ApiPageSeriesJSON[]>([]);
  const [statistics, setStatistics] =
    useState<ApiPageWritingStatisticsJSON | null>(null);
  const [loadedView, setLoadedView] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const requestGeneration = useRef(0);
  const view = `${bookcase}-${shelf}`;

  useEffect(() => {
    const generation = ++requestGeneration.current;
    if (!signedIn) return;

    const request =
      bookcase === 'mine'
        ? shelf === 'pages'
          ? apiGetPages()
          : apiGetPageSeries()
        : shelf === 'pages'
          ? apiGetFeaturedPages()
          : apiGetOtherPageSeries();

    void request
      .then((data) => {
        if (requestGeneration.current !== generation) return;
        if (shelf === 'pages') {
          setPages(data as ApiPageJSON[]);
          setBooklets([]);
          setHasMore(bookcase === 'mine' && data.length === PAGE_LIST_LIMIT);
        } else {
          setBooklets(data as ApiPageSeriesJSON[]);
          setPages([]);
          setHasMore(false);
        }
        setLoadedView(view);
        setLoading(false);
      })
      .catch(() => {
        if (requestGeneration.current !== generation) return;
        setPages([]);
        setBooklets([]);
        setHasMore(false);
        setLoadedView(view);
        setLoading(false);
      });
  }, [bookcase, shelf, signedIn, view]);

  useEffect(() => {
    if (!signedIn || !showWritingStatistics || statistics) return;

    void apiGetPageWritingStatistics()
      .then(setStatistics)
      .catch(() => undefined);
  }, [showWritingStatistics, signedIn, statistics]);

  const handleLoadMore = useCallback(() => {
    if (
      !signedIn ||
      loading ||
      !hasMore ||
      bookcase !== 'mine' ||
      shelf !== 'pages'
    )
      return;
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
  }, [bookcase, hasMore, loading, pages.length, shelf, signedIn]);

  const initialLoading = signedIn && loadedView !== view;
  const mine = bookcase === 'mine';
  const showMyBookcase = useCallback(() => {
    setBookcase('mine');
  }, []);
  const showPublicBookcase = useCallback(() => {
    setBookcase('public');
  }, []);
  const showPages = useCallback(() => {
    setShelf('pages');
  }, []);
  const showBooklets = useCallback(() => {
    setShelf('booklets');
  }, []);
  const changePageSetting = useCallback(
    (key: string[], checked: boolean) => {
      dispatch(changeLocalSetting(['pages', ...key], checked));
    },
    [dispatch],
  );

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
      />
      <div className='account__section-headline page-index__bookcases'>
        <button
          type='button'
          className={mine ? 'active' : undefined}
          onClick={showMyBookcase}
        >
          <FormattedMessage
            id='pages.bookcase.mine'
            defaultMessage='My bookcase'
          />
        </button>
        <button
          type='button'
          className={!mine ? 'active' : undefined}
          onClick={showPublicBookcase}
        >
          <FormattedMessage
            id='pages.bookcase.public'
            defaultMessage='Public bookcase'
          />
        </button>
      </div>
      <div className='page-index__controls'>
        <div className='page-index__tabs' role='tablist'>
          <button
            type='button'
            role='tab'
            aria-selected={shelf === 'pages'}
            className={shelf === 'pages' ? 'active' : undefined}
            onClick={showPages}
          >
            {mine ? (
              <FormattedMessage id='pages.tab.mine' defaultMessage='My pages' />
            ) : (
              <FormattedMessage
                id='pages.tab.featured'
                defaultMessage='Featured pages'
              />
            )}
          </button>
          <button
            type='button'
            role='tab'
            aria-selected={shelf === 'booklets'}
            className={shelf === 'booklets' ? 'active' : undefined}
            onClick={showBooklets}
          >
            {mine ? (
              <FormattedMessage
                id='pages.tab.my_booklets'
                defaultMessage='My Booklets'
              />
            ) : (
              <FormattedMessage
                id='pages.tab.other_booklets'
                defaultMessage='Public Booklets'
              />
            )}
          </button>
        </div>
        {signedIn && mine && (
          <div className='page-index__display-settings'>
            <SettingToggle
              prefix='pages'
              settings={pageSettings}
              settingPath={['show_activity']}
              onChange={changePageSetting}
              label={intl.formatMessage(messages.showActivity)}
              defaultValue
            />
          </div>
        )}
      </div>
      {signedIn &&
        mine &&
        shelf === 'pages' &&
        showWritingStatistics &&
        statistics && (
          <WritingStatistics
            statistics={statistics}
            showReport={showWritingReport}
            reportToggle={
              <SettingToggle
                prefix='pages'
                settings={pageSettings}
                settingPath={['show_report']}
                onChange={changePageSetting}
                label={intl.formatMessage(messages.showReport)}
                defaultValue
              />
            }
          />
        )}
      {signedIn && mine && (
        <div className='page-index__create-actions'>
          <Link
            to={shelf === 'pages' ? '/pages/new' : '/pages/booklets/new'}
            className='button'
          >
            <Icon id='plus' icon={AddIcon} />
            {intl.formatMessage(
              shelf === 'pages' ? messages.createPage : messages.createBooklet,
            )}
          </Link>
        </div>
      )}
      <ScrollableList
        scrollKey={`pages-${view}`}
        onLoadMore={handleLoadMore}
        hasMore={loadedView === view && hasMore}
        isLoading={loading || initialLoading}
        showLoading={initialLoading}
        emptyMessage={
          shelf === 'booklets' ? (
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
        ) : shelf === 'pages' ? (
          pages.map((page) => <PageListItem key={page.id} page={page} />)
        ) : (
          booklets.map((booklet) => (
            <BookletListItem key={booklet.id} booklet={booklet} owned={mine} />
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
