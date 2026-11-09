import type { ComponentPropsWithoutRef, FC, ReactNode } from 'react';

import classNames from 'classnames';
import { Link } from 'react-router-dom';

import type {
  ApiAccountJSON,
  BaseApiAccountJSON,
} from 'flavours/glitch/api_types/accounts';
import { Avatar } from 'flavours/glitch/components/avatar';
import { DisplayName } from 'flavours/glitch/components/display_name';
import type { Account } from 'flavours/glitch/models/account';
import { createAccountFromServerJSON } from 'flavours/glitch/models/account';

export type ChatAccount = Pick<
  BaseApiAccountJSON,
  'id' | 'acct' | 'display_name' | 'avatar' | 'avatar_static'
> &
  Partial<
    Omit<
      BaseApiAccountJSON,
      'id' | 'acct' | 'display_name' | 'avatar' | 'avatar_static'
    >
  >;

const records = new WeakMap<ChatAccount, Account>();

export const chatAccountRecord = (account: ChatAccount): Account => {
  const known = records.get(account);
  if (known) return known;
  const record = createAccountFromServerJSON({
    ...account,
    username: account.username ?? account.acct.split('@')[0] ?? account.acct,
    note: account.note ?? '',
    fields: account.fields ?? [],
    emojis: account.emojis ?? [],
    uri: account.uri ?? '',
  } as ApiAccountJSON);
  records.set(account, record);
  return record;
};

export const ChatDisplayName: FC<{
  account: ChatAccount;
  withHandle?: boolean;
}> = ({ account, withHandle = false }) =>
  withHandle ? (
    <DisplayName
      account={chatAccountRecord(account)}
      title={`@${account.acct}`}
    />
  ) : (
    <DisplayName account={chatAccountRecord(account)} variant='simple' />
  );

export const ChatLinkedDisplayName: FC<{ account: ChatAccount }> = ({
  account,
}) => (
  <Link
    className='chat-native__linked-name'
    to={`/@${account.acct}`}
    data-hover-card-account={account.id}
  >
    <ChatDisplayName account={account} withHandle />
  </Link>
);

export const ChatAvatar: FC<{
  account: ChatAccount;
  size?: number;
  withLink?: boolean;
}> = ({ account, size = 36, withLink = false }) => (
  <Avatar
    account={chatAccountRecord(account)}
    size={size}
    withLink={withLink}
  />
);

type RowTarget =
  | { kind: 'static' }
  | { kind: 'profile' }
  | ({ kind: 'button' } & Omit<ComponentPropsWithoutRef<'button'>, 'type'> &
      Partial<Record<`data-${string}`, string>>);

export const ChatAccountRow: FC<{
  account: ChatAccount;
  target?: RowTarget;
  name?: ReactNode;
  details?: ReactNode;
  className?: string;
  children?: ReactNode;
}> = ({
  account,
  target = { kind: 'static' },
  name,
  details,
  className,
  children,
}) => {
  const record = chatAccountRecord(account);
  const contents = (
    <>
      <span className='account__avatar-wrapper'>
        <Avatar account={record} size={36} />
      </span>
      <span className='account__contents'>
        {name ?? <ChatDisplayName account={account} withHandle />}
        {details !== undefined && (
          <span className='account__details'>{details}</span>
        )}
      </span>
    </>
  );

  let main: ReactNode;
  if (target.kind === 'button') {
    const { kind: _, className: buttonClassName, ...buttonProps } = target;
    main = (
      <button
        type='button'
        className={classNames('account__display-name', buttonClassName)}
        {...buttonProps}
      >
        {contents}
      </button>
    );
  } else if (target.kind === 'profile') {
    main = (
      <Link
        className='account__display-name'
        to={`/@${account.acct}`}
        title={`@${account.acct}`}
        data-hover-card-account={account.id}
      >
        {contents}
      </Link>
    );
  } else {
    main = <span className='account__display-name'>{contents}</span>;
  }

  return (
    <div
      className={classNames(
        'account account--minimal chat-native__account',
        className,
      )}
    >
      <div className='account__wrapper'>
        {main}
        {children && <div className='account__relationship'>{children}</div>}
      </div>
    </div>
  );
};
