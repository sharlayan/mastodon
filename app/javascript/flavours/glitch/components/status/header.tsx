import type { FC, HTMLAttributes, MouseEventHandler, ReactNode } from 'react';

import { defineMessage, useIntl } from 'react-intl';

import classNames from 'classnames';

import type { Map as ImmutableMap } from 'immutable';

import type {
  Account,
  AccountShapeFull,
} from '@/flavours/glitch/models/account';
import type { Status, StatusShape } from '@/flavours/glitch/models/status';
import { selectAccountStatus } from '@/flavours/glitch/selectors/statuses';
import { useAppSelector } from '@/flavours/glitch/store';

import { Avatar } from '../avatar';
import { AvatarOverlay } from '../avatar_overlay';
import type { DisplayNameProps } from '../display_name';
import { LinkedDisplayName } from '../display_name';
import { RelativeTimestamp } from '../relative_timestamp';

export interface StatusHeaderProps {
  statusId: string;
  status?: Status;
  account?: Account | AccountShapeFull;
  avatarSize?: number;
  contentBeforeDate?: ReactNode;
  contentAfterDate?: ReactNode;
  wrapperProps?: HTMLAttributes<HTMLDivElement>;
  displayNameProps?: DisplayNameProps;
  onHeaderClick?: MouseEventHandler<HTMLDivElement>;
  className?: string;
  featured?: boolean;
  mediaIcons?: string[];
  settings?: ImmutableMap<string, unknown>;
  collapseEnabled?: boolean;
  collapseButtonCharacterLimit?: number | null;
  collapsed?: boolean;
  setCollapsed?: (value: boolean) => void;
}

export type StatusHeaderRenderFn = (args: StatusHeaderProps) => ReactNode;

export const StatusHeader: FC<StatusHeaderProps> = ({
  statusId,
  account,
  className,
  avatarSize = 48,
  wrapperProps,
  contentBeforeDate,
  contentAfterDate,
  onHeaderClick,
}) => {
  const status = useAppSelector((state) =>
    selectAccountStatus(state, statusId),
  );
  if (!status) {
    return null;
  }
  const statusAccount = status.account;

  return (
    /* eslint-disable jsx-a11y/no-static-element-interactions, jsx-a11y/click-events-have-key-events */
    <header
      onClick={onHeaderClick}
      onAuxClick={onHeaderClick}
      {...wrapperProps}
      className={classNames('status__info', className)}
      /* eslint-enable jsx-a11y/no-static-element-interactions, jsx-a11y/click-events-have-key-events */
    >
      <StatusDisplayName
        statusAccount={statusAccount}
        friendAccount={account}
        avatarSize={avatarSize}
        status={status}
      />

      {contentBeforeDate}
      {contentAfterDate}
    </header>
  );
};

const editMessage = defineMessage({
  id: 'status.edited',
  defaultMessage: 'Edited {date}',
});

const StatusEditedAt: FC<{ editedAt: string }> = ({ editedAt }) => {
  const intl = useIntl();
  return (
    <abbr
      title={intl.formatMessage(editMessage, {
        date: intl.formatDate(editedAt, {
          year: 'numeric',
          month: 'short',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
        }),
      })}
    >
      {' '}
      *
    </abbr>
  );
};

const StatusDisplayName: FC<{
  statusAccount?: AccountShapeFull;
  friendAccount?: Account | AccountShapeFull;
  avatarSize: number;
  status: Pick<StatusShape, 'created_at' | 'edited_at'>;
}> = ({ statusAccount, friendAccount, avatarSize, status }) => {
  const AccountComponent = friendAccount ? AvatarOverlay : Avatar;
  return (
    <LinkedDisplayName
      displayProps={{
        account: statusAccount,
        children: (
          <span className='status__display-name__created-time'>
            <RelativeTimestamp timestamp={status.created_at} />
            {status.edited_at && <StatusEditedAt editedAt={status.edited_at} />}
          </span>
        ),
      }}
      className='status__display-name'
    >
      <div className='status__avatar'>
        <AccountComponent
          account={statusAccount}
          friend={friendAccount}
          size={avatarSize}
        />
      </div>
    </LinkedDisplayName>
  );
};
