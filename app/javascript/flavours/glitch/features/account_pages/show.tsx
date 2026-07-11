import { useEffect, useState } from 'react';

import { useHistory, useParams } from 'react-router-dom';

import { apiGetAccountPage } from '@/flavours/glitch/api/pages';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import { BundleColumnError } from '@/flavours/glitch/features/ui/components/bundle_column_error';
import Column from '@/flavours/glitch/features/ui/components/column';
import { useAccountId } from '@/flavours/glitch/hooks/useAccountId';

const AccountPage: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const history = useHistory();
  const accountId = useAccountId();
  const { name } = useParams<{ name: string }>();
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    if (!accountId) {
      return;
    }

    let active = true;

    apiGetAccountPage(accountId, name)
      .then((page) => {
        if (active) {
          history.replace(`/pages/${page.id}`);
        }

        return page;
      })
      .catch(() => {
        if (active) {
          setNotFound(true);
        }
      });

    return () => {
      active = false;
    };
  }, [accountId, history, name]);

  if (accountId === null || notFound) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  return (
    <Column>
      <LoadingIndicator />
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default AccountPage;
