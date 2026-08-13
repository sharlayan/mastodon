import { useCallback, useState, useEffect } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { useParams, Link } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import GroupIcon from '@/material-icons/400-24px/group.svg?react';
import SquigglyArrow from '@/svg-icons/squiggly_arrow.svg?react';
import { fetchRelationships } from 'flavours/glitch/actions/accounts';
import { showAlertForError } from 'flavours/glitch/actions/alerts';
import { fetchCircle } from 'flavours/glitch/actions/circles';
import { importFetchedAccounts } from 'flavours/glitch/actions/importer';
import {
  apiGetCircleAccounts,
  apiAddAccountToCircle,
  apiRemoveAccountFromCircle,
} from 'flavours/glitch/api/circles';
import { Avatar } from 'flavours/glitch/components/avatar';
import { VerifiedBadge } from 'flavours/glitch/components/badge';
import { Button } from 'flavours/glitch/components/button';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { ColumnSearchHeader } from 'flavours/glitch/components/column/search_header';
import { FollowersCounter } from 'flavours/glitch/components/counters';
import { DisplayName } from 'flavours/glitch/components/display_name';
import ScrollableList from 'flavours/glitch/components/scrollable_list';
import { ShortNumber } from 'flavours/glitch/components/short_number';
import { useSearchAccounts } from 'flavours/glitch/hooks/useSearchAccounts';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

export const messages = defineMessages({
  manageMembers: {
    id: 'column.circle_members',
    defaultMessage: 'Manage circle members',
  },
  placeholder: {
    id: 'circles.search',
    defaultMessage: 'Search among people who follow you',
  },
  add: { id: 'circles.add_member', defaultMessage: 'Add' },
  remove: { id: 'circles.remove_member', defaultMessage: 'Remove' },
  back: { id: 'column_back_button.label', defaultMessage: 'Back' },
});

type Mode = 'remove' | 'add';

const AccountItem: React.FC<{
  accountId: string;
  circleId: string;
  partOfCircle: boolean;
  onToggle: (accountId: string) => void;
}> = ({ accountId, circleId, partOfCircle, onToggle }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const account = useAppSelector((state) => state.accounts.get(accountId));

  useEffect(() => {
    if (accountId) {
      dispatch(fetchRelationships([accountId]));
    }
  }, [dispatch, accountId]);

  const handleClick = useCallback(() => {
    if (partOfCircle) {
      void apiRemoveAccountFromCircle(circleId, accountId);
      onToggle(accountId);
    } else {
      apiAddAccountToCircle(circleId, accountId)
        .then(() => {
          onToggle(accountId);
          return '';
        })
        .catch((err: unknown) => {
          dispatch(showAlertForError(err));
        });
    }
  }, [dispatch, accountId, circleId, partOfCircle, onToggle]);

  if (!account) {
    return null;
  }

  const firstVerifiedField = account.fields.find((item) => !!item.verified_at);

  return (
    <div className='account'>
      <div className='account__wrapper'>
        <Link
          key={account.id}
          className='account__display-name'
          title={account.acct}
          to={`/@${account.acct}`}
          data-hover-card-account={account.id}
        >
          <div className='account__avatar-wrapper'>
            <Avatar account={account} size={36} />
          </div>

          <div className='account__contents'>
            <DisplayName account={account} />

            <div className='account__details'>
              <ShortNumber
                value={account.followers_count}
                renderer={FollowersCounter}
              />{' '}
              {firstVerifiedField && (
                <VerifiedBadge link={firstVerifiedField.value} />
              )}
            </div>
          </div>
        </Link>

        <div className='account__relationship'>
          <Button
            text={intl.formatMessage(
              partOfCircle ? messages.remove : messages.add,
            )}
            secondary={partOfCircle}
            onClick={handleClick}
          />
        </div>
      </div>
    </div>
  );
};

const CircleMembers: React.FC<{
  multiColumn?: boolean;
}> = ({ multiColumn }) => {
  const dispatch = useAppDispatch();
  const { id } = useParams<{ id: string }>();
  const intl = useIntl();

  const [searching, setSearching] = useState(false);
  const [accountIds, setAccountIds] = useState<string[]>([]);
  const [loading, setLoading] = useState(!!id);
  const [mode, setMode] = useState<Mode>('remove');

  const {
    accounts: accountsFromSearch,
    isLoading: loadingSearchResults,
    searchAccounts: handleSearch,
  } = useSearchAccounts({
    resetOnInputClear: false,
    onSettled: (value) => {
      if (value.trim().length === 0) {
        setSearching(false);
      } else {
        setSearching(true);
      }
    },
  });
  const accountIdsFromSearch = accountsFromSearch.map((item) => item.id);

  useEffect(() => {
    if (id) {
      dispatch(fetchCircle(id));

      void apiGetCircleAccounts(id)
        .then((data) => {
          dispatch(importFetchedAccounts(data));
          setAccountIds(data.map((a) => a.id));
          setLoading(false);
          return '';
        })
        .catch(() => {
          setLoading(false);
        });
    }
  }, [dispatch, id]);

  const handleSearchClick = useCallback(() => {
    setMode('add');
  }, [setMode]);

  const handleDismissSearchClick = useCallback(() => {
    setMode('remove');
    setSearching(false);
  }, [setMode]);

  const handleAccountToggle = useCallback(
    (accountId: string) => {
      const partOfCircle = accountIds.includes(accountId);

      if (partOfCircle) {
        setAccountIds(accountIds.filter((account) => account !== accountId));
      } else {
        setAccountIds([accountId, ...accountIds]);
      }
    },
    [accountIds, setAccountIds],
  );

  let displayedAccountIds: string[];

  if (mode === 'add' && searching) {
    displayedAccountIds = accountIdsFromSearch;
  } else {
    displayedAccountIds = accountIds;
  }

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.manageMembers)}
    >
      <ColumnHeader
        title={intl.formatMessage(messages.manageMembers)}
        icon='group'
        iconComponent={GroupIcon}
        multiColumn={multiColumn}
        showBackButton
      />

      <ColumnSearchHeader
        placeholder={intl.formatMessage(messages.placeholder)}
        onBack={handleDismissSearchClick}
        onSubmit={handleSearch}
        onActivate={handleSearchClick}
        active={mode === 'add'}
      />

      <ScrollableList
        scrollKey='circle_members'
        trackScroll={!multiColumn}
        bindToDocument={!multiColumn}
        isLoading={loading || loadingSearchResults}
        showLoading={loading && displayedAccountIds.length === 0}
        hasMore={false}
        footer={
          <>
            {displayedAccountIds.length > 0 && <div className='spacer' />}

            <div className='column-footer'>
              <Link to={`/circles/${id}/edit`} className='button button--block'>
                <FormattedMessage id='circles.done' defaultMessage='Done' />
              </Link>
            </div>
          </>
        }
        emptyMessage={
          mode === 'remove' ? (
            <>
              <span>
                <FormattedMessage
                  id='circles.no_members_yet'
                  defaultMessage='No members yet.'
                />
                <br />
                <FormattedMessage
                  id='circles.find_users_to_add'
                  defaultMessage='Find people who follow you to add'
                />
              </span>

              <SquigglyArrow className='empty-column-indicator__arrow' />
            </>
          ) : (
            <FormattedMessage
              id='circles.no_results_found'
              defaultMessage='No results found.'
              tagName='span'
            />
          )
        }
      >
        {displayedAccountIds.map((accountId) => (
          <AccountItem
            key={accountId}
            accountId={accountId}
            circleId={id}
            partOfCircle={
              displayedAccountIds === accountIds ||
              accountIds.includes(accountId)
            }
            onToggle={handleAccountToggle}
          />
        ))}
      </ScrollableList>

      <Helmet>
        <title>{intl.formatMessage(messages.manageMembers)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default CircleMembers;
