import type React from 'react';
import { useCallback, useEffect, useId, useState } from 'react';

import { FormattedMessage, useIntl } from 'react-intl';

import { useHistory } from 'react-router-dom';

import { directCompose } from 'flavours/glitch/actions/compose';
import { apiRequest } from 'flavours/glitch/api';
import type { ApiAccountJSON } from 'flavours/glitch/api_types/accounts';
import { Avatar } from 'flavours/glitch/components/avatar';
import { Button } from 'flavours/glitch/components/button';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { useAccountHandle } from 'flavours/glitch/components/display_name/default';
import { ComboboxField } from 'flavours/glitch/components/form_fields';
import { useComboboxItemProps } from 'flavours/glitch/components/form_fields/combobox_field';
import {
  ListItemContent,
  ListItemWrapper,
} from 'flavours/glitch/components/list_item';
import { useAccount } from 'flavours/glitch/hooks/useAccount';
import { useSearchAccounts } from 'flavours/glitch/hooks/useSearchAccounts';
import { domain } from 'flavours/glitch/initial_state';
import { useAppDispatch } from 'flavours/glitch/store';

import classes from './mention_search.module.scss';

const getItemId = (account: ApiAccountJSON) => account.id;

const SuggestedAccountItem: React.FC<{ id: string }> = ({ id }) => {
  const account = useAccount(id);
  const handle = useAccountHandle(account, domain);
  const comboboxItemProps = useComboboxItemProps();

  if (!account) return null;

  return (
    <li {...comboboxItemProps} className={classes.suggestion}>
      <ListItemWrapper icon={<Avatar account={account} size={40} />}>
        <ListItemContent subtitle={handle}>
          <DisplayName account={account} variant='simple' />
        </ListItemContent>
      </ListItemWrapper>
    </li>
  );
};

const renderAccountItem = (account: ApiAccountJSON) => (
  <SuggestedAccountItem id={account.id} />
);

const SelectedAccount: React.FC<{
  accountId: string;
  onMention: () => void;
}> = ({ accountId, onMention }) => {
  const account = useAccount(accountId);
  const handle = useAccountHandle(account, domain);
  const history = useHistory();

  const [conversationId, setConversationId] = useState<string | null>(null);
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    let active = true;

    apiRequest<{ id: string | null }>(
      'GET',
      `v1/conversations/with_account/${accountId}`,
    )
      .then((data) => {
        if (active) {
          setConversationId(data.id);
          setChecking(false);
        }
        return data;
      })
      .catch(() => {
        if (active) {
          setChecking(false);
        }
      });

    return () => {
      active = false;
    };
  }, [accountId]);

  const handleOpen = useCallback(() => {
    if (conversationId) {
      history.push(`/conversations/${conversationId}`);
    }
  }, [conversationId, history]);

  if (!account) return null;

  return (
    <div className={classes.selected}>
      <ListItemWrapper icon={<Avatar account={account} size={40} />}>
        <ListItemContent subtitle={handle}>
          <DisplayName account={account} variant='simple' />
        </ListItemContent>
      </ListItemWrapper>
      {conversationId ? (
        <Button compact onClick={handleOpen}>
          <FormattedMessage
            id='mention_search.open_conversation'
            defaultMessage='Open conversation'
          />
        </Button>
      ) : (
        <Button compact secondary onClick={onMention} disabled={checking}>
          <FormattedMessage
            id='mention_search.mention'
            defaultMessage='Message'
          />
        </Button>
      )}
    </div>
  );
};

export const MentionSearch: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const inputId = useId();

  const [searchValue, setSearchValue] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const selectedAccount = useAccount(selectedId);

  const { accounts, isLoading, searchAccounts, resetAccounts } =
    useSearchAccounts();

  const handleSearchValueChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setSearchValue(e.target.value);
      searchAccounts(e.target.value);
    },
    [searchAccounts],
  );

  const handleSearchKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Enter') {
        e.preventDefault();
      }
    },
    [],
  );

  const handleSelectItem = useCallback(
    (item: ApiAccountJSON) => {
      setSelectedId(item.id);
      setSearchValue('');
      resetAccounts();
    },
    [resetAccounts],
  );

  const handleMention = useCallback(() => {
    if (selectedAccount) {
      dispatch(directCompose(selectedAccount));
      setSelectedId(null);
    }
  }, [dispatch, selectedAccount]);

  return (
    <div className={classes.wrapper}>
      <ComboboxField
        openOnFocus
        id={inputId}
        label={intl.formatMessage({
          id: 'mention_search.label',
          defaultMessage: 'Search for a user to message',
        })}
        value={searchValue}
        onChange={handleSearchValueChange}
        onKeyDown={handleSearchKeyDown}
        isLoading={isLoading}
        items={accounts}
        getItemId={getItemId}
        renderItem={renderAccountItem}
        onSelectItem={handleSelectItem}
      />

      {selectedId && (
        <SelectedAccount
          key={selectedId}
          accountId={selectedId}
          onMention={handleMention}
        />
      )}
    </div>
  );
};
