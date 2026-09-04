import { useCallback, useState, useEffect } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { useParams, Link } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import GroupIcon from '@/material-icons/400-24px/group.svg?react';
import {
  expandFollowers,
  fetchFollowers,
  fetchRelationships,
} from 'flavours/glitch/actions/accounts';
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
import { me } from 'flavours/glitch/initial_state';
import { selectUserListWithoutMe } from 'flavours/glitch/selectors/user_lists';
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
  members: { id: 'circles.members', defaultMessage: 'Members' },
  addMembers: { id: 'circles.add_members', defaultMessage: 'Add members' },
  back: { id: 'column_back_button.label', defaultMessage: 'Back' },
});

type Tab = 'members' | 'add';

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
  const [searchActive, setSearchActive] = useState(false);
  const [accountIds, setAccountIds] = useState<string[]>([]);
  const [loading, setLoading] = useState(!!id);
  const [tab, setTab] = useState<Tab>('members');
  const followerList = useAppSelector((state) =>
    selectUserListWithoutMe(state, 'followers', me),
  );

  const {
    accounts: accountsFromSearch,
    isLoading: loadingSearchResults,
    searchAccounts: handleSearch,
    resetAccounts: resetSearchAccounts,
  } = useSearchAccounts({
    followersOnly: true,
    onSettled: (value) => {
      if (value.trim().length === 0) {
        setSearching(false);
      } else {
        setSearching(true);
      }
    },
  });
  const accountIdsFromSearch = accountsFromSearch.map((item) => item.id);
  const followerIds = followerList?.items ?? [];

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

  useEffect(() => {
    if (me && !followerList) {
      dispatch(fetchFollowers(me));
    }
  }, [dispatch, followerList]);

  const handleSelectMembers = useCallback(() => {
    setTab('members');
    setSearchActive(false);
    setSearching(false);
    resetSearchAccounts();
  }, [resetSearchAccounts]);

  const handleSelectAdd = useCallback(() => {
    setTab('add');
  }, []);

  const handleSearchClick = useCallback(() => {
    setSearchActive(true);
  }, []);

  const handleDismissSearchClick = useCallback(() => {
    setSearchActive(false);
    setSearching(false);
    resetSearchAccounts();
    handleSearch('');
  }, [handleSearch, resetSearchAccounts]);

  const handleLoadMore = useCallback(() => {
    if (me) {
      dispatch(expandFollowers(me));
    }
  }, [dispatch]);

  const handleAccountToggle = useCallback((accountId: string) => {
    setAccountIds((currentAccountIds) =>
      currentAccountIds.includes(accountId)
        ? currentAccountIds.filter((account) => account !== accountId)
        : [accountId, ...currentAccountIds],
    );
  }, []);

  const displayedAccountIds =
    tab === 'members'
      ? accountIds
      : searching
        ? accountIdsFromSearch
        : followerIds;
  const isLoading =
    loading ||
    (tab === 'add' &&
      (loadingSearchResults ||
        (!searching && (followerList?.isLoading ?? true))));

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

      <div className='account__section-headline' role='tablist'>
        <button
          type='button'
          role='tab'
          aria-selected={tab === 'members'}
          className={tab === 'members' ? 'active' : undefined}
          onClick={handleSelectMembers}
        >
          <FormattedMessage {...messages.members} />
        </button>
        <button
          type='button'
          role='tab'
          aria-selected={tab === 'add'}
          className={tab === 'add' ? 'active' : undefined}
          onClick={handleSelectAdd}
        >
          <FormattedMessage {...messages.addMembers} />
        </button>
      </div>

      {tab === 'add' && (
        <ColumnSearchHeader
          placeholder={intl.formatMessage(messages.placeholder)}
          onBack={handleDismissSearchClick}
          onSubmit={handleSearch}
          onActivate={handleSearchClick}
          active={searchActive}
        />
      )}

      <ScrollableList
        scrollKey={`circle_members_${tab}`}
        trackScroll={!multiColumn}
        bindToDocument={!multiColumn}
        isLoading={isLoading}
        showLoading={isLoading && displayedAccountIds.length === 0}
        hasMore={tab === 'add' && !searching && followerList?.hasMore}
        onLoadMore={handleLoadMore}
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
          tab === 'members' ? (
            <FormattedMessage
              id='circles.no_members_yet'
              defaultMessage='No members yet.'
              tagName='span'
            />
          ) : searching ? (
            <FormattedMessage
              id='circles.no_results_found'
              defaultMessage='No results found.'
              tagName='span'
            />
          ) : (
            <FormattedMessage
              id='circles.no_followers'
              defaultMessage='No followers available to add.'
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
            partOfCircle={accountIds.includes(accountId)}
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
