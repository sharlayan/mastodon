import PropTypes from 'prop-types';
import { FormattedMessage } from 'react-intl';

import { MentionSearch } from 'flavours/glitch/components/mention_search';

export const SharlayanConversationsListPrepend = ({ prepend }) => (
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

SharlayanConversationsListPrepend.propTypes = {
  prepend: PropTypes.node,
};
