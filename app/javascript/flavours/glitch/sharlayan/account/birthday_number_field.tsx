import type { FC } from 'react';

import { FormattedMessage, useIntl } from 'react-intl';

import { NumberFieldsItem } from '@/flavours/glitch/components/number_fields';

import { parseBirthday } from './birthday';

export const SharlayanBirthdayNumberField: FC<{ birthday?: string | null }> = ({
  birthday,
}) => {
  const intl = useIntl();
  const date = parseBirthday(birthday);

  if (!date) return null;

  return (
    <NumberFieldsItem
      label={
        <FormattedMessage
          id='account.birthday_short'
          defaultMessage='Birthday'
        />
      }
      hint={intl.formatDate(date, {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        timeZone: 'UTC',
      })}
    >
      {intl.formatDate(date, {
        month: 'short',
        day: '2-digit',
        timeZone: 'UTC',
      })}
    </NumberFieldsItem>
  );
};
