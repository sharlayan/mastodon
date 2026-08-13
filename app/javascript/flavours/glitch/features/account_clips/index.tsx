import { useEffect } from 'react';

import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import { fetchAccountClips } from '@/flavours/glitch/actions/clips';
import { AccountHeader } from '@/flavours/glitch/components/account_header';
import { Column } from '@/flavours/glitch/components/column';
import { ColumnBackButton } from '@/flavours/glitch/components/column/back_button';
import { Icon } from '@/flavours/glitch/components/icon';
import { LoadingIndicator } from '@/flavours/glitch/components/loading_indicator';
import { RemoteHint } from '@/flavours/glitch/components/remote_hint';
import {
  ItemList,
  Scrollable,
} from '@/flavours/glitch/components/scrollable_list/components';
import { BundleColumnError } from '@/flavours/glitch/features/ui/components/bundle_column_error';
import { useAccountId } from '@/flavours/glitch/hooks/useAccountId';
import { useAccountVisibility } from '@/flavours/glitch/hooks/useAccountVisibility';
import { getOrderedAccountClips } from '@/flavours/glitch/selectors/clips';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';

import { ClipFavouriteButton } from '../clips/components/favourite_button';

const AccountClips: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const accountId = useAccountId();
  const { suspended, blockedBy, hidden } = useAccountVisibility(accountId);
  const forceEmptyState = suspended || blockedBy || hidden;

  const dispatch = useAppDispatch();

  useEffect(() => {
    if (accountId) {
      void dispatch(fetchAccountClips({ accountId }));
    }
  }, [accountId, dispatch]);

  const clips = useAppSelector((state) =>
    getOrderedAccountClips(state, accountId),
  );

  if (accountId === null) {
    return <BundleColumnError multiColumn={multiColumn} errorType='routing' />;
  }

  return (
    <Column>
      <ColumnBackButton />

      <Scrollable>
        {accountId && (
          <AccountHeader accountId={accountId} hideTabs={forceEmptyState} />
        )}

        {!accountId ? (
          <div className='scrollable__append'>
            <LoadingIndicator />
          </div>
        ) : clips.length === 0 ? (
          <div className='empty-column-indicator'>
            <FormattedMessage
              id='empty_column.account_clips'
              defaultMessage='No clips here.'
            />
          </div>
        ) : (
          <ItemList>
            {clips.map((clip) => (
              <div key={clip.id} className='lists__item'>
                <Link to={`/clips/${clip.id}`} className='lists__item__title'>
                  <Icon
                    id={clip.public ? 'globe' : 'lock'}
                    icon={clip.public ? PublicIcon : LockIcon}
                  />
                  <span>{clip.title}</span>
                  <span className='lists__item__count'>
                    <FormattedMessage
                      id='clips.statuses_count'
                      defaultMessage='{count, plural, one {# post} other {# posts}}'
                      values={{ count: clip.statuses_count }}
                    />
                  </span>
                </Link>
                <ClipFavouriteButton
                  clip={clip}
                  className='clip-favourite-button star-icon'
                />
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
export default AccountClips;
