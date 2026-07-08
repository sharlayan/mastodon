import { useCallback } from 'react';

import PropTypes from 'prop-types';
import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { useDispatch, useSelector } from 'react-redux';

import BarChart4BarsIcon from '@/material-icons/400-24px/bar_chart_4_bars.svg?react';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import PhotoLibraryIcon from '@/material-icons/400-24px/photo_library.svg?react';
import { cancelReplyCompose } from 'flavours/glitch/actions/compose';
import { Avatar } from 'flavours/glitch/components/avatar';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { Permalink } from 'flavours/glitch/components/permalink';
import { EmbeddedStatusContent } from 'flavours/glitch/features/notifications_v2/components/embedded_status_content';

const messages = defineMessages({
  cancel: { id: 'reply_indicator.cancel', defaultMessage: 'Cancel' },
});

export const ReplyIndicator = ({ isInline }) => {
  const intl = useIntl();
  const dispatch = useDispatch();
  const inReplyToId = useSelector(state => state.getIn(['compose', 'in_reply_to']));
  const status = useSelector(state => state.getIn(['statuses', inReplyToId]));
  const account = useSelector(state => state.getIn(['accounts', status?.get('account')]));

  const handleCancelClick = useCallback(() => {
    dispatch(cancelReplyCompose());
  }, [dispatch]);

  if (!status) {
    return null;
  }

  return (
    <div className='reply-indicator'>
      <div className='reply-indicator__line' />

      <Permalink href={account.get('url')} to={`/@${account.get('acct')}`} className='detailed-status__display-avatar'>
        <Avatar key={`avatar-${account.get('id')}`} account={account} size={46} />
      </Permalink>

      <div className='reply-indicator__main'>
        <div className='reply-indicator__header'>
          <Permalink href={account.get('url')} to={`/@${account.get('acct')}`} className='detailed-status__display-name'>
            <DisplayName account={account} />
          </Permalink>

          {isInline && (
            <div className='reply-indicator__cancel'>
              <IconButton title={intl.formatMessage(messages.cancel)} icon='times' iconComponent={CloseIcon} onClick={handleCancelClick} inverted />
            </div>
          )}
        </div>

        <EmbeddedStatusContent
          className='reply-indicator__content translate'
          status={status}
        />

        {(status.get('poll') || status.get('media_attachments').size > 0) && (
          <div className='reply-indicator__attachments'>
            {status.get('poll') && <><Icon icon={BarChart4BarsIcon} /><FormattedMessage id='reply_indicator.poll' defaultMessage='Poll' /></>}
            {status.get('media_attachments').size > 0 && <><Icon icon={PhotoLibraryIcon} /><FormattedMessage id='reply_indicator.attachments' defaultMessage='{count, plural, one {# attachment} other {# attachments}}' values={{ count: status.get('media_attachments').size }} /></>}
          </div>
        )}
      </div>
    </div>
  );
};

ReplyIndicator.propTypes = {
  isInline: PropTypes.bool,
};
