import { useEffect, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import { apiGetAccountPages } from '@/flavours/glitch/api/pages';
import type { ApiPageJSON } from '@/flavours/glitch/api_types/pages';
import { AccountHeader } from '@/flavours/glitch/components/account_header';
import { ColumnBackButton } from '@/flavours/glitch/components/column_back_button';
import { Icon } from '@/flavours/glitch/components/icon';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import { RemoteHint } from '@/flavours/glitch/components/remote_hint';
import {
  ItemList,
  Scrollable,
} from '@/flavours/glitch/components/scrollable_list/components';
import { BundleColumnError } from '@/flavours/glitch/features/ui/components/bundle_column_error';
import Column from '@/flavours/glitch/features/ui/components/column';
import { useAccountId } from '@/flavours/glitch/hooks/useAccountId';
import { useAccountVisibility } from '@/flavours/glitch/hooks/useAccountVisibility';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';

const AccountPages: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const accountId = useAccountId();
  const { suspended, blockedBy, hidden } = useAccountVisibility(accountId);
  const forceEmptyState = suspended || blockedBy || hidden;

  const [fetchedPages, setFetchedPages] = useState<ApiPageJSON[] | null>(null);

  useEffect(() => {
    if (accountId && !forceEmptyState) {
      apiGetAccountPages(accountId)
        .then((data) => {
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

  return (
    <Column>
      <ColumnBackButton />

      <Scrollable>
        {accountId && (
          <AccountHeader accountId={accountId} hideTabs={forceEmptyState} />
        )}

        {pages === null ? (
          <div className='scrollable__append'>
            <LoadingIndicator />
          </div>
        ) : pages.length === 0 ? (
          <div className='empty-column-indicator'>
            <FormattedMessage
              id='empty_column.account_pages'
              defaultMessage='No pages here.'
            />
          </div>
        ) : (
          <ItemList>
            {pages.map((page) => (
              <div key={page.id} className='lists__item'>
                <Link to={`/pages/${page.id}`} className='lists__item__title'>
                  <Icon id='description' icon={DescriptionIcon} />
                  <span>{page.title || page.name}</span>
                </Link>
              </div>
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
