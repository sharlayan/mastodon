import { useCallback, useEffect, useMemo, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import { showAlertForError } from 'flavours/glitch/actions/alerts';
import { importFetchedAccounts } from 'flavours/glitch/actions/importer';
import {
  apiGetStatusReactionAccounts,
  STATUS_REACTION_ACCOUNTS_PAGE_SIZE,
} from 'flavours/glitch/api/status_reactions';
import type { ApiStatusReactionAccountJSON } from 'flavours/glitch/api/status_reactions';
import { Account } from 'flavours/glitch/components/account';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { LoadMore } from 'flavours/glitch/components/load_more';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { useAppDispatch } from 'flavours/glitch/store';

type ReactionMap = ImmutableMap<string, string | number | boolean>;

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
});

const ReactionIcon: React.FC<{ reaction: ReactionMap }> = ({ reaction }) => {
  const name = reaction.get('name') as string;
  const url = reaction.get('static_url') as string | undefined;

  return url ? (
    <img src={url} alt={`:${name}:`} className='emojione custom-emoji' />
  ) : (
    <span>{name}</span>
  );
};

export const StatusReactionsModal: React.FC<{
  statusId: string;
  reactions: ImmutableList<ReactionMap>;
  onClose: () => void;
}> = ({ statusId, reactions, onClose }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const visibleReactions = useMemo(
    () =>
      reactions
        .filter((reaction) => (reaction.get('count') as number) > 0)
        .sort(
          (left, right) =>
            (right.get('count') as number) - (left.get('count') as number),
        ),
    [reactions],
  );
  const [selectedName, setSelectedName] = useState(
    () => visibleReactions.first()?.get('name') as string | undefined,
  );
  const [items, setItems] = useState<ApiStatusReactionAccountJSON[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasMore, setHasMore] = useState(false);

  const loadMore = useCallback(async () => {
    if (!selectedName) return;

    setLoading(true);
    try {
      const page = await apiGetStatusReactionAccounts(
        statusId,
        selectedName,
        items.at(-1)?.id,
      );
      dispatch(importFetchedAccounts(page.map((item) => item.account)));
      const nextItems = [...items, ...page];
      setItems(nextItems);
      setHasMore(page.length === STATUS_REACTION_ACCOUNTS_PAGE_SIZE);
    } catch (error) {
      dispatch(showAlertForError(error));
    } finally {
      setLoading(false);
    }
  }, [dispatch, items, selectedName, statusId]);

  const handleLoadMore = useCallback(() => {
    void loadMore();
  }, [loadMore]);

  const handleSelectReaction = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      const name = event.currentTarget.dataset.name;
      if (!name || name === selectedName) return;

      setItems([]);
      setHasMore(false);
      setLoading(true);
      setSelectedName(name);
    },
    [selectedName],
  );

  useEffect(() => {
    let active = true;

    if (!selectedName) {
      return;
    }

    void apiGetStatusReactionAccounts(statusId, selectedName)
      .then((page) => {
        if (!active) return;
        dispatch(importFetchedAccounts(page.map((item) => item.account)));
        setItems(page);
        setHasMore(page.length === STATUS_REACTION_ACCOUNTS_PAGE_SIZE);
      })
      .catch((error: unknown) => {
        if (active) dispatch(showAlertForError(error));
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [dispatch, selectedName, statusId]);

  return (
    <div className='modal-root__modal status-reactions-modal'>
      <div className='status-reactions-modal__header'>
        <h1>
          <FormattedMessage id='status.reactions' defaultMessage='Reactions' />
        </h1>
        <IconButton
          title={intl.formatMessage(messages.close)}
          icon='close'
          iconComponent={CloseIcon}
          onClick={onClose}
        />
      </div>

      <div className='status-reactions-modal__tabs'>
        {visibleReactions.map((reaction) => {
          const name = reaction.get('name') as string;
          return (
            <button
              type='button'
              key={name}
              data-name={name}
              className={name === selectedName ? 'active' : undefined}
              onClick={handleSelectReaction}
            >
              <ReactionIcon reaction={reaction} />
              <span>{reaction.get('count') as number}</span>
            </button>
          );
        })}
      </div>

      <div className='status-reactions-modal__list'>
        {items.map((item) => (
          <Account key={item.id} id={item.account.id} minimal />
        ))}
        {loading && items.length === 0 && (
          <div className='status-reactions-modal__loading'>
            <LoadingIndicator />
          </div>
        )}
        {items.length > 0 && (
          <LoadMore
            visible={hasMore}
            loading={loading}
            onClick={handleLoadMore}
          />
        )}
      </div>
    </div>
  );
};
