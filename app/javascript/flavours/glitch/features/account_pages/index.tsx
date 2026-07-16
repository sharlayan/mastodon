import { useEffect, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { apiGetAccountPages } from '@/flavours/glitch/api/pages';
import type { ApiPageJSON } from '@/flavours/glitch/api_types/pages';
import { AccountHeader } from '@/flavours/glitch/components/account_header';
import { ColumnBackButton } from '@/flavours/glitch/components/column_back_button';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import { RemoteHint } from '@/flavours/glitch/components/remote_hint';
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
  const { suspended, blockedBy, hidden } = useAccountVisibility(accountId);
  const forceEmptyState = suspended || blockedBy || hidden;

  const [fetchedPages, setFetchedPages] = useState<ApiPageJSON[] | null>(null);
  const [category, setCategory] = useState('');

  useEffect(() => {
    if (accountId && !forceEmptyState) {
      apiGetAccountPages(accountId)
        .then((data) => {
          setCategory('');
          setFetchedPages(data);
          return data;
        })
        .catch(() => {
          setFetchedPages([]);
        });
    }
  }, [accountId, forceEmptyState]);

  if (accountId === null) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  const pages = forceEmptyState ? [] : fetchedPages;
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

        {accountId && <RemoteHint accountId={accountId} />}
      </Scrollable>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default AccountPages;
