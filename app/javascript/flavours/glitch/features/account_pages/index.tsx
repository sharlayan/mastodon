import { useCallback, useEffect, useRef, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import {
  apiGetAccountPages,
  PAGE_LIST_LIMIT,
} from '@/flavours/glitch/api/pages';
import type { ApiPageJSON } from '@/flavours/glitch/api_types/pages';
import { AccountHeader } from '@/flavours/glitch/components/account_header';
import { ColumnBackButton } from '@/flavours/glitch/components/column_back_button';
import { LoadMore } from '@/flavours/glitch/components/load_more';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import { RemoteHint } from '@/flavours/glitch/components/remote_hint';
import { useAppHistory } from '@/flavours/glitch/components/router';
import {
  ItemList,
  Scrollable,
} from '@/flavours/glitch/components/scrollable_list/components';
import { CategoryFilter } from '@/flavours/glitch/features/pages/components/category_filter';
import { PageListItem } from '@/flavours/glitch/features/pages/components/page_list_item';
import { BundleColumnError } from '@/flavours/glitch/features/ui/components/bundle_column_error';
import Column from '@/flavours/glitch/features/ui/components/column';
import { useAccountId } from '@/flavours/glitch/hooks/useAccountId';
import { useAccountVisibility } from '@/flavours/glitch/hooks/useAccountVisibility';

const AccountPages: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const accountId = useAccountId();
  const history = useAppHistory();
  const { suspended, blockedBy, hidden } = useAccountVisibility(accountId);
  const forceEmptyState = suspended || blockedBy || hidden;

  const [fetchedPages, setFetchedPages] = useState<ApiPageJSON[] | null>(null);
  const [fetchedAccountId, setFetchedAccountId] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [category, setCategory] = useState('');
  const requestGeneration = useRef(0);

  useEffect(() => {
    const generation = ++requestGeneration.current;

    if (accountId && !forceEmptyState) {
      apiGetAccountPages(accountId)
        .then((data) => {
          if (requestGeneration.current === generation) {
            setCategory('');
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

  useEffect(() => {
    const mainPage = fetchedPages?.find((page) => page.is_main);

    if (mainPage && mainPage.account_id === accountId) {
      history.replace(
        `/@${mainPage.account.acct}/pages/${encodeURIComponent(mainPage.name)}`,
      );
    }
  }, [accountId, fetchedPages, history]);

  if (accountId === null) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  const pages =
    forceEmptyState || fetchedAccountId === accountId
      ? forceEmptyState
        ? []
        : fetchedPages
      : null;
  const visiblePages =
    pages && category
      ? pages.filter((page) => page.category === category)
      : pages;

  return (
    <Column>
      <ColumnBackButton />

      <Scrollable>
        {accountId && (
          <AccountHeader accountId={accountId} hideTabs={forceEmptyState} />
        )}

        {pages && (
          <CategoryFilter
            pages={pages}
            value={category}
            onChange={setCategory}
          />
        )}

        {visiblePages === null ? (
          <div className='scrollable__append'>
            <LoadingIndicator />
          </div>
        ) : visiblePages.length === 0 ? (
          <div className='empty-column-indicator'>
            <FormattedMessage
              id='empty_column.account_pages'
              defaultMessage='No pages here.'
            />
          </div>
        ) : (
          <ItemList>
            {visiblePages.map((page) => (
              <PageListItem key={page.id} page={page} />
            ))}
          </ItemList>
        )}

        {pages && hasMore && (
          <LoadMore onClick={handleLoadMore} loading={loadingMore} />
        )}

        {accountId && <RemoteHint accountId={accountId} />}
      </Scrollable>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default AccountPages;
