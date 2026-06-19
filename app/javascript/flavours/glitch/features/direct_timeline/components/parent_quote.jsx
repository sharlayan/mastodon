import PropTypes from 'prop-types';
import { useCallback, useEffect, useRef } from 'react';

import { FormattedMessage } from 'react-intl';

import { useHistory } from 'react-router-dom';

import { useDispatch, useSelector } from 'react-redux';

import { fetchStatus } from 'flavours/glitch/actions/statuses';
import { Avatar } from 'flavours/glitch/components/avatar';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { EmojiHTML } from 'flavours/glitch/components/emoji/html';
import { VisibilityIcon } from 'flavours/glitch/components/visibility_icon';
import { makeGetStatus } from 'flavours/glitch/selectors';

const getStatus = makeGetStatus();

export const ParentQuote = ({ statusId }) => {
  const dispatch = useDispatch();
  const history = useHistory();

  const status = useSelector(state => getStatus(state, { id: statusId }));
  const isInStore = useSelector(state => state.getIn(['statuses', statusId], null) !== null);

  const didFetchRef = useRef(false);

  useEffect(() => {
    didFetchRef.current = false;
  }, [statusId]);

  useEffect(() => {
    if (!isInStore && !didFetchRef.current) {
      didFetchRef.current = true;
      dispatch(fetchStatus(statusId, { alsoFetchContext: false }));
    }
  }, [dispatch, statusId, isInStore]);

  const account = status ? status.get('account') : null;

  const handleClick = useCallback(() => {
    if (account) {
      history.push(`/@${account.get('acct')}/${status.get('id')}`);
    }
  }, [history, account, status]);

  if (!status || !account || status.get('visibility') === 'direct') {
    return null;
  }

  return (
    <button type='button' className='chat-message__parent' onClick={handleClick}>
      <div className='chat-message__parent__header'>
        <Avatar account={account} size={16} />
        <DisplayName account={account} variant='simple' />
        <VisibilityIcon visibility={status.get('visibility')} />
        <span className='chat-message__parent__label'>
          <FormattedMessage id='direct_conversation.in_reply_to' defaultMessage='In reply to' />
        </span>
      </div>

      <EmojiHTML
        className='chat-message__parent__content'
        htmlString={status.get('contentHtml')}
        extraEmojis={status.get('emojis')}
      />
    </button>
  );
};

ParentQuote.propTypes = {
  statusId: PropTypes.string.isRequired,
};
