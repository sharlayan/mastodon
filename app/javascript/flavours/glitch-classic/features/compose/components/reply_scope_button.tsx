import { useCallback } from 'react';

import { FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';

import { changeComposeReplyScope } from '@/flavours/glitch-classic/actions/compose_typed';
import { Button } from '@/flavours/glitch-classic/components/button/redesign';
import { Icon } from '@/flavours/glitch-classic/components/icon';
import {
  useAppDispatch,
  useAppSelector,
} from '@/flavours/glitch-classic/store';
import ReplyIcon from '@/material-icons/400-24px/reply.svg?react';

export const ReplyScopeButton: React.FC<{
  disabled?: boolean;
  redesign?: boolean;
}> = ({ disabled = false, redesign = false }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const available = useAppSelector(
    (state) => !!state.compose.get('reply_to_limited'),
  );
  const selected = useAppSelector(
    (state) => state.compose.get('limited_scope') === 'reply',
  );
  const editing = useAppSelector((state) => !!state.compose.get('id'));
  const handleClick = useCallback(() => {
    dispatch(changeComposeReplyScope(!selected));
  }, [dispatch, selected]);

  if (!available && !selected) return null;

  const title = intl.formatMessage({
    id: 'privacy.reply.long',
    defaultMessage: 'Only the author and recipients of the original post',
  });
  const label = (
    <FormattedMessage
      id='privacy.reply.short'
      defaultMessage='Reply audience'
    />
  );

  return redesign ? (
    <Button
      size='sm'
      aria-pressed={selected}
      disabled={disabled || editing}
      onClick={handleClick}
      tooltip={{ text: title, type: 'description' }}
    >
      {label}
    </Button>
  ) : (
    <button
      type='button'
      aria-pressed={selected}
      disabled={disabled || editing}
      onClick={handleClick}
      title={title}
      className={classNames('dropdown-button', { active: selected })}
    >
      <Icon id='reply' icon={ReplyIcon} />
      <span className='dropdown-button__label'>{label}</span>
    </button>
  );
};
