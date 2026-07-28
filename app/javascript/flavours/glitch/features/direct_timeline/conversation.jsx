import PropTypes from 'prop-types';
import { useRef, useCallback, useEffect, useLayoutEffect, useMemo } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import { useParams } from 'react-router-dom';

import { List as ImmutableList } from 'immutable';
import { useDispatch, useSelector } from 'react-redux';

import GroupIcon from '@/material-icons/400-24px/group.svg?react';
import MailIcon from '@/material-icons/400-24px/mail.svg?react';
import { addColumn, removeColumn, moveColumn } from 'flavours/glitch/actions/columns';
import { markConversationRead, expandConversationStatuses } from 'flavours/glitch/actions/conversations';
import { openModal } from 'flavours/glitch/actions/modal';
import { dismissNotificationsForStatuses } from 'flavours/glitch/actions/notification_groups';
import { connectDirectStream } from 'flavours/glitch/actions/streaming';
import { isNonStatusId } from 'flavours/glitch/actions/timelines_typed';
import { CircularProgress } from 'flavours/glitch/components/circular_progress';
import Column from 'flavours/glitch/components/column';
import ColumnHeader from 'flavours/glitch/components/column_header';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { me } from 'flavours/glitch/initial_state';

import { ChatMessage } from './components/chat_message';
import { DirectComposer } from './components/direct_composer';

const messages = defineMessages({
  title: { id: 'column.conversation', defaultMessage: 'Conversation' },
  participants: { id: 'conversation.show_participants', defaultMessage: 'Show participants' },
  titleSingle: { id: 'direct_conversation.title_single', defaultMessage: 'Conversation with {name1}' },
  titleDouble: { id: 'direct_conversation.title_double', defaultMessage: 'Conversation with {name1} and {name2}' },
  titleMore: { id: 'direct_conversation.title_more', defaultMessage: 'Conversation with {name1}, {name2} and {count, plural, one {# other} other {# others}}' },
});

const ConversationThread = ({ multiColumn, columnId, params }) => {
  const { conversationId: routeConversationId } = useParams();
  const conversationId = params?.id ?? routeConversationId;
  const pinned = !!columnId;
  const intl = useIntl();
  const dispatch = useDispatch();
  const columnRef = useRef();
  const messagesRef = useRef();
  const timelineId = `conversation:${conversationId}`;

  const conversation = useSelector(state => state.getIn(['conversations', 'items']).find(item => item.get('id') === conversationId));

  const items = useSelector(state => state.getIn(['timelines', timelineId, 'items']) || ImmutableList());
  const isLoading = useSelector(state => state.getIn(['timelines', timelineId, 'isLoading'], false));
  const hasMore = useSelector(state => state.getIn(['timelines', timelineId, 'hasMore'], false));

  const statusIds = useMemo(() => items.filter(id => id && !isNonStatusId(id)), [items]);

  const statuses = useSelector(state => state.get('statuses'));

  const recipientIds = useMemo(() => {
    if (conversation) {
      return conversation.get('accounts').toArray();
    }

    const ids = [];
    const seen = new Set();

    statusIds.forEach(id => {
      const status = statuses.get(id);

      if (!status) {
        return;
      }

      const authorId = status.get('account');

      if (authorId && authorId !== me && !seen.has(authorId)) {
        seen.add(authorId);
        ids.push(authorId);
      }

      (status.get('mentions') || ImmutableList()).forEach(mention => {
        const mentionId = mention.get('id');

        if (mentionId && mentionId !== me && !seen.has(mentionId)) {
          seen.add(mentionId);
          ids.push(mentionId);
        }
      });
    });

    return ids;
  }, [conversation, statusIds, statuses]);

  const recipientAccounts = useSelector(state => recipientIds
    .map(id => state.getIn(['accounts', id]))
    .filter(Boolean));

  const nameNode = useCallback(account => (
    <DisplayName key={account.get('id')} account={account} variant='simple' />
  ), []);

  let headerTitle = <FormattedMessage {...messages.title} />;

  if (recipientAccounts.length === 1) {
    headerTitle = <FormattedMessage {...messages.titleSingle} values={{ name1: nameNode(recipientAccounts[0]) }} />;
  } else if (recipientAccounts.length === 2) {
    headerTitle = <FormattedMessage {...messages.titleDouble} values={{ name1: nameNode(recipientAccounts[0]), name2: nameNode(recipientAccounts[1]) }} />;
  } else if (recipientAccounts.length > 2) {
    headerTitle = <FormattedMessage {...messages.titleMore} values={{ name1: nameNode(recipientAccounts[0]), name2: nameNode(recipientAccounts[1]), count: recipientAccounts.length - 2 }} />;
  }

  // Timelines are stored newest-first; render chronologically (oldest → newest)
  // for a chat-like layout with the latest message at the bottom.
  const orderedIds = useMemo(() => statusIds.reverse(), [statusIds]);
  const oldestId = statusIds.last();
  const latestId = statusIds.first();

  const notificationGroups = useSelector(state => state.notificationGroups.groups);

  const unreadNotificationStatusIds = useMemo(() => {
    const present = new Set(statusIds.toArray());

    return notificationGroups
      .filter(group =>
        group.type !== 'gap' &&
        (group.type === 'mention' || group.type === 'quote' || group.type === 'reaction') &&
        'statusId' in group &&
        group.statusId &&
        present.has(group.statusId))
      .map(group => group.statusId);
  }, [notificationGroups, statusIds]);

  const unreadNotificationKey = unreadNotificationStatusIds.join(',');

  useEffect(() => {
    if (unreadNotificationStatusIds.length > 0) {
      dispatch(dismissNotificationsForStatuses(unreadNotificationStatusIds));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dispatch, unreadNotificationKey]);

  const scrollToBottom = useCallback(() => {
    const node = messagesRef.current;

    if (node) {
      node.scrollTop = node.scrollHeight;
    }
  }, []);

  useEffect(() => {
    dispatch(expandConversationStatuses(conversationId));
    dispatch(markConversationRead(conversationId));

    const disconnect = dispatch(connectDirectStream());

    return () => {
      disconnect();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dispatch, conversationId]);

  useEffect(() => {
    // The body-height fix is only needed for the single-column (route) view;
    // pinned deck columns are already height-bounded by the columns layout.
    if (multiColumn) {
      return undefined;
    }

    document.body.classList.add('conversation-detail-active');

    return () => {
      document.body.classList.remove('conversation-detail-active');
    };
  }, [multiColumn]);

  // Re-arm the initial pin-to-bottom for each thread (same route reuses the
  // component instance across conversation switches).
  const didInitialScrollRef = useRef(false);

  useEffect(() => {
    didInitialScrollRef.current = false;
  }, [conversationId]);

  useLayoutEffect(() => {
    if (!latestId) {
      return;
    }

    scrollToBottom();

    if (didInitialScrollRef.current) {
      return;
    }

    didInitialScrollRef.current = true;

    const raf = requestAnimationFrame(scrollToBottom);
    const t1 = setTimeout(scrollToBottom, 200);
    const t2 = setTimeout(scrollToBottom, 500);

    return () => {
      cancelAnimationFrame(raf);
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [latestId, scrollToBottom]);

  const handleShowParticipants = useCallback(() => {
    dispatch(openModal({
      modalType: 'CONVERSATION_PARTICIPANTS',
      modalProps: { accountIds: recipientIds },
    }));
  }, [dispatch, recipientIds]);

  const handleLoadMore = useCallback(() => {
    if (oldestId && hasMore && !isLoading) {
      dispatch(expandConversationStatuses(conversationId, { maxId: oldestId }));
    }
  }, [dispatch, conversationId, oldestId, hasMore, isLoading]);

  const handlePin = useCallback(() => {
    if (columnId) {
      dispatch(removeColumn(columnId));
    } else {
      dispatch(addColumn('CONVERSATION', { id: conversationId }));
    }
  }, [dispatch, columnId, conversationId]);

  const handleMove = useCallback(dir => {
    dispatch(moveColumn(columnId, dir));
  }, [dispatch, columnId]);

  const handleHeaderClick = useCallback(() => {
    columnRef.current?.scrollTop();
  }, []);

  const participantsButton = recipientAccounts.length > 0 ? (
    <IconButton
      className='column-header__button'
      icon='group'
      iconComponent={GroupIcon}
      title={intl.formatMessage(messages.participants)}
      onClick={handleShowParticipants}
    />
  ) : undefined;

  return (
    <Column bindToDocument={!multiColumn} ref={columnRef} label={intl.formatMessage(messages.title)}>
      <ColumnHeader
        icon='envelope'
        iconComponent={MailIcon}
        title={headerTitle}
        onPin={handlePin}
        onMove={handleMove}
        onClick={handleHeaderClick}
        pinned={pinned}
        multiColumn={multiColumn}
        showBackButton={!pinned}
        extraButton={participantsButton}
      />

      <div className='conversation-thread'>
        <div className='conversation-thread__body'>
          <div className='conversation-thread__messages' ref={messagesRef}>
            {hasMore && !isLoading && (
              <button className='conversation-thread__load-more' onClick={handleLoadMore}>
                <FormattedMessage id='direct_conversation.load_older' defaultMessage='Load older messages' />
              </button>
            )}

            {orderedIds.isEmpty() && !isLoading ? (
              <div className='conversation-thread__empty'>
                <FormattedMessage id='empty_column.direct' defaultMessage="You don't have any private mentions yet. When you send or receive one, it will show up here." />
              </div>
            ) : (
              orderedIds.map((statusId, index) => (
                <ChatMessage
                  key={statusId}
                  conversationId={conversationId}
                  statusId={statusId}
                  prevStatusId={index > 0 ? orderedIds.get(index - 1) : undefined}
                  nextStatusId={index < orderedIds.size - 1 ? orderedIds.get(index + 1) : undefined}
                />
              ))
            )}
          </div>

          {isLoading && orderedIds.isEmpty() && (
            <div className='conversation-thread__loading'>
              <CircularProgress size={32} strokeWidth={4} />
              <span><FormattedMessage id='direct_conversation.loading_recent' defaultMessage='Loading recent messages…' /></span>
            </div>
          )}
        </div>

        <DirectComposer
          conversationId={conversationId}
          inReplyToId={latestId}
          recipientIds={recipientIds}
        />
      </div>

      <Helmet>
        <title>{intl.formatMessage(messages.title)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

ConversationThread.propTypes = {
  multiColumn: PropTypes.bool,
  columnId: PropTypes.string,
  params: PropTypes.shape({
    id: PropTypes.string,
  }),
};

export default ConversationThread;
