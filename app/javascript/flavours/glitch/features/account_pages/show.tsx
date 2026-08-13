import { useEffect, useState } from 'react';

import { useParams } from 'react-router-dom';

import { apiGetAccountPage } from '@/flavours/glitch/api/pages';
import type { ApiPageJSON } from '@/flavours/glitch/api_types/pages';
import { Column } from '@/flavours/glitch/components/column';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import PageShow from '@/flavours/glitch/features/pages/show';
import { BundleColumnError } from '@/flavours/glitch/features/ui/components/bundle_column_error';
import { useAccountId } from '@/flavours/glitch/hooks/useAccountId';

const AccountPage: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const accountId = useAccountId();
  const { name } = useParams<{ name: string }>();
  const requestKey = accountId ? `${accountId}:${name}` : null;
  const [pageResult, setPageResult] = useState<{
    requestKey: string;
    page: ApiPageJSON;
  } | null>(null);
  const [notFoundKey, setNotFoundKey] = useState<string | null>(null);

  useEffect(() => {
    if (!accountId) {
      return;
    }

    let active = true;
    const currentRequestKey = `${accountId}:${name}`;

    apiGetAccountPage(accountId, name)
      .then((page) => {
        if (active) {
          setPageResult({ requestKey: currentRequestKey, page });
        }

        return page;
      })
      .catch(() => {
        if (active) {
          setNotFoundKey(currentRequestKey);
        }
      });

    return () => {
      active = false;
    };
  }, [accountId, name]);

  if (accountId === null || (requestKey && notFoundKey === requestKey)) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  const page =
    requestKey && pageResult?.requestKey === requestKey
      ? pageResult.page
      : null;

  if (page) {
    return (
      <PageShow
        key={page.id}
        multiColumn={multiColumn}
        pageId={page.id}
        initialPage={page}
      />
    );
  }

  return (
    <Column>
      <LoadingIndicator />
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default AccountPage;
