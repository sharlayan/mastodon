import { useEffect, useCallback } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import MoodIcon from '@/material-icons/400-24px/mood.svg?react';
import {
  addColumn,
  removeColumn,
  moveColumn,
} from 'flavours/glitch/actions/columns';
import {
  fetchReactedStatuses,
  expandReactedStatuses,
  fetchReactionSummary,
  setReactionFilter,
} from 'flavours/glitch/actions/reactions';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import StatusList from 'flavours/glitch/components/status_list';
import { getStatusList } from 'flavours/glitch/selectors';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { ReactionSummaryBar } from './reaction_summary_bar';

const messages = defineMessages({
  heading: { id: 'column.reactions', defaultMessage: 'Reactions' },
});

const Reactions: React.FC<{ columnId: string; multiColumn: boolean }> = ({
  columnId,
  multiColumn,
}) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const statusIds = useAppSelector((state) =>
    getStatusList(state, 'reactions'),
  );
  const isLoading = useAppSelector(
    (state) =>
      state.status_lists.getIn(['reactions', 'isLoading'], true) as boolean,
  );
  const hasMore = useAppSelector(
    (state) => !!state.status_lists.getIn(['reactions', 'next']),
  );
  const reactionSummary = useAppSelector((state) =>
    state.status_lists.get('reactionSummary'),
  );
  const reactionFilter = useAppSelector(
    (state) => state.status_lists.get('reactionFilter') as string | null,
  );

  useEffect(() => {
    dispatch(fetchReactedStatuses());
    dispatch(fetchReactionSummary());
  }, [dispatch]);

  const handlePin = useCallback(() => {
    if (columnId) {
      dispatch(removeColumn(columnId));
    } else {
      dispatch(addColumn('REACTIONS', {}));
    }
  }, [dispatch, columnId]);

  const handleMove = useCallback(
    (dir: number) => {
      dispatch(moveColumn(columnId, dir));
    },
    [dispatch, columnId],
  );

  const handleLoadMore = useCallback(() => {
    dispatch(expandReactedStatuses());
  }, [dispatch]);

  const handleFilterChange = useCallback(
    (name: string | null) => {
      dispatch(setReactionFilter(name));
    },
    [dispatch],
  );

  const pinned = !!columnId;

  const emptyMessage = (
    <FormattedMessage
      id='empty_column.reacted_statuses'
      defaultMessage="You don't have any reacted posts yet. When you react to one, it will show up here."
    />
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='mood'
        iconComponent={MoodIcon}
        title={intl.formatMessage(messages.heading)}
        onPin={handlePin}
        onMove={handleMove}
        scrollTopOnClick
        pinned={pinned}
        multiColumn={multiColumn}
        showBackButton
      >
        <ReactionSummaryBar
          summary={reactionSummary}
          activeFilter={reactionFilter}
          onFilterChange={handleFilterChange}
        />
      </ColumnHeader>

      <StatusList
        trackScroll={!pinned}
        statusIds={statusIds}
        scrollKey={`reacted_statuses-${columnId}`}
        hasMore={hasMore}
        isLoading={isLoading}
        onLoadMore={handleLoadMore}
        emptyMessage={emptyMessage}
        bindToDocument={!multiColumn}
        timelineId='reactions'
      />

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default Reactions;
