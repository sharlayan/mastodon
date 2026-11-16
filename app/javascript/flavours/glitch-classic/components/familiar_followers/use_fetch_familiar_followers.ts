import { useEffect } from 'react';

import { fetchAccountsFamiliarFollowers } from '@/flavours/glitch-classic/actions/accounts_familiar_followers';
import { useIdentity } from '@/flavours/glitch-classic/identity_context';
import { getAccountFamiliarFollowers } from '@/flavours/glitch-classic/selectors/accounts';
import {
  useAppDispatch,
  useAppSelector,
} from '@/flavours/glitch-classic/store';
import { me } from 'flavours/glitch-classic/initial_state';

export const useFetchFamiliarFollowers = ({
  accountId,
}: {
  accountId?: string;
}) => {
  const dispatch = useAppDispatch();
  const familiarFollowers = useAppSelector((state) =>
    accountId ? getAccountFamiliarFollowers(state, accountId) : null,
  );
  const { signedIn } = useIdentity();

  const hasNoData = familiarFollowers === null;

  useEffect(() => {
    if (hasNoData && signedIn && accountId && accountId !== me) {
      void dispatch(fetchAccountsFamiliarFollowers({ id: accountId }));
    }
  }, [dispatch, accountId, hasNoData, signedIn]);

  return {
    familiarFollowers: hasNoData ? [] : familiarFollowers,
    isLoading: hasNoData,
  };
};
