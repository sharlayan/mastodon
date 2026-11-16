import type { FC } from 'react';

import { FormattedMessage } from 'react-intl';

import { FollowersCounter } from './counters';
import { ShortNumber } from './short_number';

export const AccountFollowersCount: FC<{
  value: number;
  withLabel?: boolean;
}> = ({ value, withLabel = false }) => {
  if (value < 0) {
    return withLabel ? (
      <span>
        <FormattedMessage id='account.followers' defaultMessage='Followers' />
      </span>
    ) : (
      <span>-</span>
    );
  }

  return (
    <ShortNumber
      value={value}
      renderer={withLabel ? FollowersCounter : undefined}
    />
  );
};
