import PropTypes from 'prop-types';
import { useRef, useMemo, useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import { useSelector, useDispatch } from 'react-redux';

import { debounce } from 'lodash';

import { expandConversations } from 'flavours/glitch/actions/conversations';
import { MentionSearch } from 'flavours/glitch/components/mention_search';
import ScrollableList from 'flavours/glitch/components/scrollable_list';

import { Conversation } from './conversation';

export const ConversationsList = ({ scrollKey, prepend, ...other }) => {
  const listRef = useRef();
  const conversations = useSelector(state => state.getIn(['conversations', 'items']));
  const isLoading = useSelector(state => state.getIn(['conversations', 'isLoading'], true));
  const hasMore = useSelector(state => state.getIn(['conversations', 'hasMore'], false));
  const dispatch = useDispatch();
  const lastStatusId = conversations.last()?.get('last_status');

  const debouncedLoadMore = useMemo(() => debounce(id => {
    dispatch(expandConversations({ maxId: id }));
  }, 300, { leading: true }), [dispatch]);

  const handleLoadMore = useCallback(() => {
    if (lastStatusId) {
      debouncedLoadMore(lastStatusId);
    }
  }, [debouncedLoadMore, lastStatusId]);

  const listPrepend = (
    <>
      <div className='conversations-list__new'>
        <h4 className='conversations-list__new-heading'>
          <FormattedMessage id='direct.start_conversation' defaultMessage='Start a new conversation' />
        </h4>
        <MentionSearch />
      </div>
      {prepend}
    </>
  );

  return (
    <ScrollableList {...other} prepend={listPrepend} alwaysPrepend scrollKey={scrollKey} isLoading={isLoading} showLoading={isLoading && conversations.isEmpty()} hasMore={hasMore} onLoadMore={handleLoadMore} disableAutoLoad ref={listRef}>
      {conversations.map(item => (
        <Conversation
          key={item.get('id')}
          conversation={item}
          scrollKey={scrollKey}
        />
      ))}
    </ScrollableList>
  );
};

ConversationsList.propTypes = {
  scrollKey: PropTypes.string.isRequired,
  prepend: PropTypes.node,
};
