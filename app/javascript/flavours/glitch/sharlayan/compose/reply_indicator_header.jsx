import { useCallback } from 'react';

import PropTypes from 'prop-types';
import { defineMessages, useIntl } from 'react-intl';
import { useDispatch } from 'react-redux';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import { cancelReplyCompose } from 'flavours/glitch/actions/compose';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { Permalink } from 'flavours/glitch/components/permalink';

const messages = defineMessages({
  cancel: { id: 'reply_indicator.cancel', defaultMessage: 'Cancel' },
});

export const SharlayanReplyIndicatorHeader = ({ account }) => {
  const intl = useIntl();
  const dispatch = useDispatch();

  const handleCancelClick = useCallback(() => {
    dispatch(cancelReplyCompose());
  }, [dispatch]);

  return (
    <div className='reply-indicator__header'>
      <Permalink href={account.get('url')} to={`/@${account.get('acct')}`} className='detailed-status__display-name'>
        <DisplayName account={account} />
      </Permalink>

      <div className='reply-indicator__cancel'>
        <IconButton title={intl.formatMessage(messages.cancel)} icon='times' iconComponent={CloseIcon} onClick={handleCancelClick} inverted />
      </div>
    </div>
  );
};

SharlayanReplyIndicatorHeader.propTypes = {
  account: PropTypes.object.isRequired,
};
