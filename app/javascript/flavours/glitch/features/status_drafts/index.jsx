import { useCallback, useEffect, useRef } from 'react';

import { Helmet } from '@unhead/react/helmet';
import { List as ImmutableList } from 'immutable';
import { defineMessages, FormattedMessage, useIntl } from 'react-intl';
import { useDispatch, useSelector } from 'react-redux';

import DraftIcon from '@/material-icons/400-24px/save.svg?react';
import { fetchStatusDrafts } from 'flavours/glitch/actions/status_drafts';
import Column from 'flavours/glitch/components/column';
import ColumnHeader from 'flavours/glitch/components/column_header';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import ScrollableList from 'flavours/glitch/components/scrollable_list';

import { StatusDraftCard } from './status_draft_card';

const messages = defineMessages({
  title: { id: 'column.drafts', defaultMessage: 'Drafts' },
  empty: { id: 'empty_column.drafts', defaultMessage: 'You do not have any saved drafts.' },
});

const StatusDrafts = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useDispatch();
  const columnRef = useRef();
  const items = useSelector(state => state.getIn(['status_drafts', 'items'])) || ImmutableList();
  const isLoading = useSelector(state => state.getIn(['status_drafts', 'isLoading']));
  const setRef = useCallback(column => { columnRef.current = column; }, []);

  useEffect(() => {
    dispatch(fetchStatusDrafts());
  }, [dispatch]);

  return (
    <Column bindToDocument={!multiColumn} ref={setRef} label={intl.formatMessage(messages.title)}>
      <ColumnHeader
        icon='drafts'
        iconComponent={DraftIcon}
        title={intl.formatMessage(messages.title)}
        onClick={() => columnRef.current?.scrollTop()}
        multiColumn={multiColumn}
      />
      {isLoading && items.size === 0 ? <LoadingIndicator /> : (
        <ScrollableList
          scrollKey='status-drafts'
          trackScroll={false}
          emptyMessage={<FormattedMessage {...messages.empty} />}
          bindToDocument={!multiColumn}
        >
          {items.map(draft => <StatusDraftCard key={draft.get('id')} draft={draft} />)}
        </ScrollableList>
      )}
      <Helmet>
        <title>{intl.formatMessage(messages.title)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

export default StatusDrafts;
