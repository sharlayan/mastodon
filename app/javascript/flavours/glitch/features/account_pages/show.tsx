import { useCallback, useEffect, useState } from 'react';

import { useParams } from 'react-router-dom';

import { isAxiosError } from 'axios';

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
  const [loadError, setLoadError] = useState<{
    requestKey: string;
    notFound: boolean;
  } | null>(null);
  const [loadAttempt, setLoadAttempt] = useState(0);

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
      .catch((error: unknown) => {
        if (active) {
          const status = isAxiosError(error)
            ? error.response?.status
            : undefined;
          setLoadError({
            requestKey: currentRequestKey,
            notFound: status === 404 || status === 410,
          });
        }
      });

    return () => {
      active = false;
    };
  }, [accountId, name, loadAttempt]);

  const handleRetryLoad = useCallback(() => {
    setLoadError(null);
    setLoadAttempt((attempt) => attempt + 1);
  }, []);

  if (accountId === null) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  if (requestKey && loadError?.requestKey === requestKey) {
    return (
      <BundleColumnError
        multiColumn={multiColumn}
        errorType={loadError.notFound ? 'routing' : 'network'}
        onRetry={handleRetryLoad}
      />
    );
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
