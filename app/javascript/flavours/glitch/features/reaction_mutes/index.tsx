import { useEffect, useCallback, useState } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import HeartBrokenIcon from '@/material-icons/400-24px/heart_broken.svg?react';
import {
  fetchReactionMutes,
  createReactionMute,
  deleteReactionMute,
} from 'flavours/glitch/actions/reaction_mutes';
import { Button } from 'flavours/glitch/components/button';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import ScrollableList from 'flavours/glitch/components/scrollable_list';
import type { ApiReactionMuteJSON } from 'flavours/glitch/initial_state';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

const messages = defineMessages({
  heading: {
    id: 'column.reaction_mutes',
    defaultMessage: 'Reaction mutes',
  },
  targetPlaceholder: {
    id: 'reaction_mutes.target_placeholder',
    defaultMessage: 'Account (@user@server) or server (example.com)',
  },
});

const ReactionMuteRow: React.FC<{
  mute: ApiReactionMuteJSON;
  onDelete: (id: string) => void;
}> = ({ mute, onDelete }) => {
  const handleClick = useCallback(() => {
    onDelete(mute.id);
  }, [mute.id, onDelete]);

  const target = mute.target_domain ?? mute.target_acct;
  const label = target ? `@${target}` : (mute.target_account_id ?? '');

  return (
    <div className='custom-emoji-mute'>
      <div className='custom-emoji-mute__info'>
        <span className='custom-emoji-mute__prefix'>{label}</span>
      </div>
      <Button onClick={handleClick}>
        <FormattedMessage id='reaction_mutes.unmute' defaultMessage='Unmute' />
      </Button>
    </div>
  );
};

const ReactionMutes: React.FC<{ multiColumn: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { items, loading } = useAppSelector((state) => state.reaction_mutes);

  const [target, setTarget] = useState('');

  useEffect(() => {
    void dispatch(fetchReactionMutes());
  }, [dispatch]);

  const handleTargetChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setTarget(event.target.value);
    },
    [],
  );

  const handleSubmit = useCallback(
    (event: React.SyntheticEvent) => {
      event.preventDefault();
      const trimmed = target.trim();
      if (!trimmed) {
        return;
      }
      if (trimmed.startsWith('@') || trimmed.includes('@')) {
        void dispatch(createReactionMute({ acct: trimmed }));
      } else {
        void dispatch(createReactionMute({ domain: trimmed }));
      }
      setTarget('');
    },
    [dispatch, target],
  );

  const handleDelete = useCallback(
    (id: string) => {
      void dispatch(deleteReactionMute({ id }));
    },
    [dispatch],
  );

  const emptyMessage = (
    <FormattedMessage
      id='empty_column.reaction_mutes'
      defaultMessage='You are not refusing reactions from anyone yet.'
    />
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='heart-o'
        iconComponent={HeartBrokenIcon}
        title={intl.formatMessage(messages.heading)}
        scrollTopOnClick
        multiColumn={multiColumn}
        showBackButton
      />

      <form className='custom-emoji-mute__form' onSubmit={handleSubmit}>
        <p className='custom-emoji-mute__hint'>
          <FormattedMessage
            id='reaction_mutes.hint'
            defaultMessage='You will not receive emoji reactions from the accounts and servers listed here. Enter an account handle (@user@server) or a whole server domain.'
          />
        </p>
        <div className='custom-emoji-mute__fields'>
          <input
            type='text'
            value={target}
            onChange={handleTargetChange}
            placeholder={intl.formatMessage(messages.targetPlaceholder)}
            aria-label={intl.formatMessage(messages.targetPlaceholder)}
          />
          <Button type='submit' disabled={!target.trim()}>
            <FormattedMessage id='reaction_mutes.add' defaultMessage='Add' />
          </Button>
        </div>
      </form>

      <ScrollableList
        scrollKey='reaction_mutes'
        emptyMessage={emptyMessage}
        isLoading={loading}
        showLoading={loading && items.length === 0}
        trackScroll={!multiColumn}
        bindToDocument={!multiColumn}
      >
        {items.map((mute) => (
          <ReactionMuteRow key={mute.id} mute={mute} onDelete={handleDelete} />
        ))}
      </ScrollableList>

      <Helmet>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default ReactionMutes;
