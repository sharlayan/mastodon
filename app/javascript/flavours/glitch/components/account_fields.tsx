import { useIntl } from 'react-intl';

import classNames from 'classnames';

import CheckIcon from '@/material-icons/400-24px/check.svg?react';
import { Icon } from 'flavours/glitch/components/icon';
import type { Account } from 'flavours/glitch/models/account';

import { EmojiHTML } from './emoji/html';
import { MfmRenderer, hasAnyMfmFn } from './mfm';
import { useElementHandledLink } from './status/handled_link';

export const AccountFields: React.FC<
  Pick<Account, 'fields' | 'emojis'> & { mfm?: boolean }
> = ({ fields, emojis, mfm = false }) => {
  const intl = useIntl();
  const htmlHandlers = useElementHandledLink();

  if (fields.size === 0) {
    return null;
  }

  return (
    <>
      {fields.map((pair, i) => (
        <dl key={i} className={classNames({ verified: pair.verified_at })}>
          <EmojiHTML
            as='dt'
            htmlString={pair.name_emojified}
            extraEmojis={emojis}
            className='translate'
            {...htmlHandlers}
          />

          <dd className='translate' title={pair.value_plain ?? ''}>
            {pair.verified_at && (
              <span
                title={intl.formatMessage(
                  {
                    id: 'account.link_verified_on',
                    defaultMessage:
                      'Ownership of this link was checked on {date}',
                  },
                  {
                    date: intl.formatDate(pair.verified_at, dateFormatOptions),
                  },
                )}
              >
                <Icon id='check' icon={CheckIcon} className='verified__mark' />
              </span>
            )}{' '}
            {mfm && hasAnyMfmFn(pair.value_plain ?? '') ? (
              <MfmRenderer
                text={pair.value_plain ?? ''}
                emojis={emojis}
                isProfile
              />
            ) : (
              <EmojiHTML
                as='span'
                htmlString={pair.value_emojified}
                extraEmojis={emojis}
                {...htmlHandlers}
              />
            )}
          </dd>
        </dl>
      ))}
    </>
  );
};

const dateFormatOptions: Intl.DateTimeFormatOptions = {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
};
