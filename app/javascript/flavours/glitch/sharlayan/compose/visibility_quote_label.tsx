import type { FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import type { ApiQuotePolicy } from '@/flavours/glitch/api_types/quotes';
import type { StatusVisibility } from '@/flavours/glitch/api_types/statuses';

const messages = defineMessages({
  public: { id: 'privacy.public.short', defaultMessage: 'Public' },
  unlisted: { id: 'privacy.unlisted.short', defaultMessage: 'Quiet public' },
  private: { id: 'privacy.private.short', defaultMessage: 'Followers' },
  direct: { id: 'privacy.direct.short', defaultMessage: 'Specific people' },
  anyone_quote: {
    id: 'privacy.quote.anyone',
    defaultMessage: '{visibility}, anyone can quote',
  },
  limited_quote: {
    id: 'privacy.quote.limited',
    defaultMessage: '{visibility}, quotes limited',
  },
  disabled_quote: {
    id: 'privacy.quote.disabled',
    defaultMessage: '{visibility}, quotes disabled',
  },
});

export const VisibilityQuoteLabel: FC<{
  visibility: StatusVisibility;
  quotePolicy: ApiQuotePolicy;
}> = ({ visibility, quotePolicy }) => {
  const intl = useIntl();
  const visibilityText = intl.formatMessage(messages[visibility]);
  if (visibility === 'private' || visibility === 'direct') {
    return <span>{visibilityText}</span>;
  }
  if (quotePolicy === 'nobody') {
    return (
      <span>
        {intl.formatMessage(messages.disabled_quote, {
          visibility: visibilityText,
        })}
      </span>
    );
  }
  if (quotePolicy !== 'public') {
    return (
      <span>
        {intl.formatMessage(messages.limited_quote, {
          visibility: visibilityText,
        })}
      </span>
    );
  }
  return (
    <span>
      {intl.formatMessage(messages.anyone_quote, {
        visibility: visibilityText,
      })}
    </span>
  );
};
