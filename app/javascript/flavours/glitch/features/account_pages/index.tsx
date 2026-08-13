import { useCallback, useEffect, useRef, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import {
  apiGetAccountPages,
  apiGetAccountPageSeries,
  PAGE_LIST_LIMIT,
} from '@/flavours/glitch/api/pages';
import type {
  ApiPageJSON,
  ApiPageSeriesJSON,
} from '@/flavours/glitch/api_types/pages';
import { AccountHeader } from '@/flavours/glitch/components/account_header';
import { Column } from '@/flavours/glitch/components/column';
import { ColumnBackButton } from '@/flavours/glitch/components/column/back_button';
import { LoadMore } from '@/flavours/glitch/components/load_more';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import { RemoteHint } from '@/flavours/glitch/components/remote_hint';
import {
  ItemList,
  Scrollable,
} from '@/flavours/glitch/components/scrollable_list/components';
import { BookletListItem } from '@/flavours/glitch/features/pages/components/booklet_list_item';
import { PageListItem } from '@/flavours/glitch/features/pages/components/page_list_item';
import { BundleColumnError } from '@/flavours/glitch/features/ui/components/bundle_column_error';
import { useAccount } from '@/flavours/glitch/hooks/useAccount';
import { useAccountId } from '@/flavours/glitch/hooks/useAccountId';
import { useAccountVisibility } from '@/flavours/glitch/hooks/useAccountVisibility';

const AccountPages: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const accountId = useAccountId();
  const account = useAccount(accountId);
  const { suspended, blockedBy, hidden } = useAccountVisibility(accountId);
  const forceEmptyState = suspended || blockedBy || hidden;

  const [fetchedPages, setFetchedPages] = useState<ApiPageJSON[] | null>(null);
  const [fetchedAccountId, setFetchedAccountId] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [tab, setTab] = useState<'pages' | 'booklets'>('pages');
  const [bookletResult, setBookletResult] = useState<{
    accountId: string;
    items: ApiPageSeriesJSON[];
  } | null>(null);
  const requestGeneration = useRef(0);

  useEffect(() => {
    const generation = ++requestGeneration.current;

    if (accountId && !forceEmptyState) {
      apiGetAccountPages(accountId)
        .then((data) => {
          if (requestGeneration.current === generation) {
            setFetchedPages(data);
            setFetchedAccountId(accountId);
            setHasMore(data.length === PAGE_LIST_LIMIT);
            setLoadingMore(false);
          }
          return data;
        })
        .catch(() => {
          if (requestGeneration.current === generation) {
            setFetchedPages([]);
            setFetchedAccountId(accountId);
            setHasMore(false);
            setLoadingMore(false);
          }
        });
    }

    return () => {
      requestGeneration.current += 1;
    };
  }, [accountId, forceEmptyState]);

  useEffect(() => {
    if (!accountId || forceEmptyState || tab !== 'booklets') return;

    void apiGetAccountPageSeries(accountId)
      .then((items) => {
        setBookletResult({ accountId, items });
      })
      .catch(() => {
        setBookletResult({ accountId, items: [] });
      });
  }, [accountId, forceEmptyState, tab]);

  const showPages = useCallback(() => {
    setTab('pages');
  }, []);
  const showBooklets = useCallback(() => {
    setTab('booklets');
  }, []);

  const handleLoadMore = useCallback(() => {
    if (
      !accountId ||
      fetchedAccountId !== accountId ||
      !fetchedPages ||
      loadingMore ||
      !hasMore
    ) {
      return;
    }

    const generation = requestGeneration.current;
    setLoadingMore(true);
    void apiGetAccountPages(accountId, fetchedPages.length)
      .then((data) => {
        if (requestGeneration.current === generation) {
          setFetchedPages((pages) => [...(pages ?? []), ...data]);
          setHasMore(data.length === PAGE_LIST_LIMIT);
          setLoadingMore(false);
        }
        return data;
      })
      .catch(() => {
        if (requestGeneration.current === generation) {
          setLoadingMore(false);
        }
      });
  }, [accountId, fetchedAccountId, fetchedPages, hasMore, loadingMore]);

  if (accountId === null) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  const pages =
    forceEmptyState || fetchedAccountId === accountId
      ? forceEmptyState
        ? []
        : fetchedPages
      : null;
  const mainPage = pages?.find((page) => page.is_main);
  const booklets =
    bookletResult && bookletResult.accountId === accountId
      ? bookletResult.items
      : null;
  const accountDisplayName = account?.get('display_name');
  const displayName = accountDisplayName?.length
    ? accountDisplayName
    : (account?.get('username') ?? '');
  return (
    <Column>
      <ColumnBackButton />

      <Scrollable>
        {accountId && (
          <AccountHeader accountId={accountId} hideTabs={forceEmptyState} />
        )}

        <div className='account__section-headline page-account__tabs'>
          <button
            type='button'
            className={tab === 'pages' ? 'active' : undefined}
            onClick={showPages}
          >
            <FormattedMessage id='account.pages' defaultMessage='Pages' />
          </button>
          <button
            type='button'
            className={tab === 'booklets' ? 'active' : undefined}
            onClick={showBooklets}
          >
            <FormattedMessage
              id='pages.tab.booklets'
              defaultMessage='Booklets'
            />
          </button>
        </div>

        {mainPage && (
          <div className='page-account__main-link'>
            <Link
              to={`/@${mainPage.account.acct}/pages/${encodeURIComponent(mainPage.name)}`}
              className='button button-secondary'
            >
              <FormattedMessage
                id='pages.account.view_main'
                defaultMessage="View {user}'s page"
                values={{ user: displayName }}
              />
            </Link>
          </div>
        )}

        {tab === 'pages' && pages === null ? (
          <div className='scrollable__append'>
            <LoadingIndicator />
          </div>
        ) : tab === 'booklets' && booklets === null ? (
          <div className='scrollable__append'>
            <LoadingIndicator />
          </div>
        ) : tab === 'pages' && pages?.length === 0 ? (
          <div className='empty-column-indicator'>
            <FormattedMessage
              id='empty_column.account_pages'
              defaultMessage='No pages here.'
            />
          </div>
        ) : tab === 'booklets' && booklets?.length === 0 ? (
          <div className='empty-column-indicator'>
            <FormattedMessage
              id='pages.booklet.none_yet'
              defaultMessage='No Booklets yet.'
            />
          </div>
        ) : tab === 'pages' && pages ? (
          <ItemList>
            {pages.map((page) => (
              <PageListItem key={page.id} page={page} />
            ))}
          </ItemList>
        ) : (
          <ItemList>
            {booklets?.map((booklet) => (
              <BookletListItem key={booklet.id} booklet={booklet} />
            ))}
          </ItemList>
        )}

        {tab === 'pages' && pages && hasMore && (
          <LoadMore onClick={handleLoadMore} loading={loadingMore} />
        )}

        {accountId && <RemoteHint accountId={accountId} />}
      </Scrollable>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default AccountPages;
