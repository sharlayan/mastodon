import { useCallback } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { unmuteDomain } from 'flavours/glitch/actions/domain_mutes';
import { useAppDispatch } from 'flavours/glitch/store';

import { Button } from './button';

const messages = defineMessages({
  hiddenFromHome: {
    id: 'account.hidden_from_home',
    defaultMessage: 'Hidden from home timeline',
  },
});

export const MutedDomain: React.FC<{
  domain: string;
  hideFromHome: boolean;
  onUnmute?: (domain: string) => void;
}> = ({ domain, hideFromHome, onUnmute }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const handleDomainUnmute = useCallback(() => {
    dispatch(unmuteDomain(domain));
    onUnmute?.(domain);
  }, [dispatch, domain, onUnmute]);

  return (
    <div className='domain'>
      <div className='domain__domain-name'>
        <strong>{domain}</strong>
        {hideFromHome && (
          <span> · {intl.formatMessage(messages.hiddenFromHome)}</span>
        )}
      </div>

      <div className='domain__buttons'>
        <Button onClick={handleDomainUnmute}>
          <FormattedMessage
            id='account.unmute_domain_short'
            defaultMessage='Unmute'
          />
        </Button>
      </div>
    </div>
  );
};
