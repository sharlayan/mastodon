import { useEffect, useCallback, useRef, useState } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import MoodIcon from '@/material-icons/400-24px/mood.svg?react';
import {
  fetchCustomEmojiMutes,
  createCustomEmojiMute,
  deleteCustomEmojiMute,
} from 'flavours/glitch/actions/custom_emoji_mutes';
import { Button } from 'flavours/glitch/components/button';
import { Column } from 'flavours/glitch/components/column';
import type { ColumnRef } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import ScrollableList from 'flavours/glitch/components/scrollable_list';
import type { ApiCustomEmojiMuteJSON } from 'flavours/glitch/initial_state';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

const messages = defineMessages({
  heading: {
    id: 'column.custom_emoji_mutes',
    defaultMessage: 'Muted custom emoji',
  },
  prefixPlaceholder: {
    id: 'custom_emoji_mutes.prefix_placeholder',
    defaultMessage: 'Shortcode prefix (e.g. blob_)',
  },
  domainPlaceholder: {
    id: 'custom_emoji_mutes.domain_placeholder',
    defaultMessage: 'Server (optional, blank = all)',
  },
});

const CustomEmojiMuteRow: React.FC<{
  mute: ApiCustomEmojiMuteJSON;
  onDelete: (id: string) => void;
}> = ({ mute, onDelete }) => {
  const handleClick = useCallback(() => {
    onDelete(mute.id);
  }, [mute.id, onDelete]);

  return (
    <div className='custom-emoji-mute'>
      <div className='custom-emoji-mute__info'>
        <span className='custom-emoji-mute__prefix'>{mute.prefix}</span>
        {mute.domain && (
          <span className='custom-emoji-mute__domain'>@{mute.domain}</span>
        )}
      </div>
      <Button onClick={handleClick}>
        <FormattedMessage
          id='custom_emoji_mutes.unmute'
          defaultMessage='Unmute'
        />
      </Button>
    </div>
  );
};

const CustomEmojiMutes: React.FC<{ multiColumn: boolean }> = ({
  multiColumn,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { items, loading } = useAppSelector(
    (state) => state.custom_emoji_mutes,
  );

  const [prefix, setPrefix] = useState('');
  const [domain, setDomain] = useState('');

  useEffect(() => {
    void dispatch(fetchCustomEmojiMutes());
  }, [dispatch]);

  const handlePrefixChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setPrefix(event.target.value);
    },
    [],
  );

  const handleDomainChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setDomain(event.target.value);
    },
    [],
  );

  const handleSubmit = useCallback(
    (event: React.FormEvent) => {
      event.preventDefault();
      const trimmed = prefix.trim();
      if (!trimmed) {
        return;
      }
      void dispatch(
        createCustomEmojiMute({ prefix: trimmed, domain: domain.trim() }),
      );
      setPrefix('');
      setDomain('');
    },
    [dispatch, prefix, domain],
  );

  const handleDelete = useCallback(
    (id: string) => {
      void dispatch(deleteCustomEmojiMute({ id }));
    },
    [dispatch],
  );

  const columnRef = useRef<ColumnRef>(null);
  const handleHeaderClick = useCallback(() => {
    columnRef.current?.scrollTop();
  }, []);

  const emptyMessage = (
    <FormattedMessage
      id='empty_column.custom_emoji_mutes'
      defaultMessage='You have not muted any custom emoji yet.'
    />
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      ref={columnRef}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='smile-o'
        iconComponent={MoodIcon}
        title={intl.formatMessage(messages.heading)}
        onClick={handleHeaderClick}
        multiColumn={multiColumn}
        showBackButton
      />

      <form className='custom-emoji-mute__form' onSubmit={handleSubmit}>
        <p className='custom-emoji-mute__hint'>
          <FormattedMessage
            id='custom_emoji_mutes.hint'
            defaultMessage='Custom emoji whose shortcode starts with the given prefix are hidden and shown as translucent text. Leave the server blank to match emoji from any server.'
          />
        </p>
        <div className='custom-emoji-mute__fields'>
          <input
            type='text'
            value={prefix}
            onChange={handlePrefixChange}
            placeholder={intl.formatMessage(messages.prefixPlaceholder)}
            aria-label={intl.formatMessage(messages.prefixPlaceholder)}
          />
          <input
            type='text'
            value={domain}
            onChange={handleDomainChange}
            placeholder={intl.formatMessage(messages.domainPlaceholder)}
            aria-label={intl.formatMessage(messages.domainPlaceholder)}
          />
          <Button type='submit' disabled={!prefix.trim()}>
            <FormattedMessage
              id='custom_emoji_mutes.add'
              defaultMessage='Add'
            />
          </Button>
        </div>
      </form>

      <ScrollableList
        scrollKey='custom_emoji_mutes'
        emptyMessage={emptyMessage}
        isLoading={loading}
        showLoading={loading && items.length === 0}
        trackScroll={!multiColumn}
        bindToDocument={!multiColumn}
      >
        {items.map((mute) => (
          <CustomEmojiMuteRow
            key={mute.id}
            mute={mute}
            onDelete={handleDelete}
          />
        ))}
      </ScrollableList>

      <Helmet>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default CustomEmojiMutes;
