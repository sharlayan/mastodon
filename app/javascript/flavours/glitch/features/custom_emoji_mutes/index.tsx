import { useEffect, useCallback, useState } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import MoodIcon from '@/material-icons/400-24px/mood.svg?react';
import {
  fetchCustomEmojiMutes,
  createCustomEmojiMute,
  deleteCustomEmojiMute,
  updateCustomEmojiMuteHidden,
} from 'flavours/glitch/actions/custom_emoji_mutes';
import { Button } from 'flavours/glitch/components/button';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
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
  onToggleReject: (mute: ApiCustomEmojiMuteJSON) => void;
  onToggleHide: (mute: ApiCustomEmojiMuteJSON) => void;
}> = ({ mute, onDelete, onToggleReject, onToggleHide }) => {
  const handleClick = useCallback(() => {
    onDelete(mute.id);
  }, [mute.id, onDelete]);

  const handleToggleReject = useCallback(() => {
    onToggleReject(mute);
  }, [mute, onToggleReject]);

  const handleToggleHide = useCallback(() => {
    onToggleHide(mute);
  }, [mute, onToggleHide]);

  return (
    <div className='custom-emoji-mute'>
      <div className='custom-emoji-mute__info'>
        <div className='custom-emoji-mute__labels'>
          <span className='custom-emoji-mute__prefix'>{mute.prefix}</span>
          {mute.domain && (
            <span className='custom-emoji-mute__domain'>@{mute.domain}</span>
          )}
        </div>
        <label className='custom-emoji-mute__checkbox'>
          <input
            type='checkbox'
            checked={mute.reject_reactions}
            onChange={handleToggleReject}
          />
          <FormattedMessage
            id='custom_emoji_mutes.reject_reactions_badge'
            defaultMessage='Reactions blocked'
          />
        </label>
        <label className='custom-emoji-mute__checkbox'>
          <input
            type='checkbox'
            checked={mute.hide_in_picker}
            onChange={handleToggleHide}
          />
          <FormattedMessage
            id='custom_emoji_mutes.hide_in_picker_badge'
            defaultMessage='Hidden in picker'
          />
        </label>
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
  const { items, loading, hidden } = useAppSelector(
    (state) => state.custom_emoji_mutes,
  );

  const [prefix, setPrefix] = useState('');
  const [domain, setDomain] = useState('');
  const [rejectReactions, setRejectReactions] = useState(false);
  const [hideInPicker, setHideInPicker] = useState(false);

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

  const handleRejectReactionsChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setRejectReactions(event.target.checked);
    },
    [],
  );

  const handleHideInPickerChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setHideInPicker(event.target.checked);
    },
    [],
  );

  const handleSubmit = useCallback(
    (event: React.SyntheticEvent) => {
      event.preventDefault();
      const trimmed = prefix.trim();
      if (!trimmed) {
        return;
      }
      void dispatch(
        createCustomEmojiMute({
          prefix: trimmed,
          domain: domain.trim(),
          reject_reactions: rejectReactions,
          hide_in_picker: hideInPicker,
        }),
      );
      setPrefix('');
      setDomain('');
      setRejectReactions(false);
      setHideInPicker(false);
    },
    [dispatch, prefix, domain, rejectReactions, hideInPicker],
  );

  const handleDelete = useCallback(
    (id: string) => {
      void dispatch(deleteCustomEmojiMute({ id }));
    },
    [dispatch],
  );

  const handleHiddenChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      void dispatch(
        updateCustomEmojiMuteHidden({ hidden: event.target.checked }),
      );
    },
    [dispatch],
  );

  const handleToggleReject = useCallback(
    (mute: ApiCustomEmojiMuteJSON) => {
      void dispatch(
        createCustomEmojiMute({
          prefix: mute.prefix,
          domain: mute.domain,
          reject_reactions: !mute.reject_reactions,
        }),
      );
    },
    [dispatch],
  );

  const handleToggleHide = useCallback(
    (mute: ApiCustomEmojiMuteJSON) => {
      void dispatch(
        createCustomEmojiMute({
          prefix: mute.prefix,
          domain: mute.domain,
          hide_in_picker: !mute.hide_in_picker,
        }),
      );
    },
    [dispatch],
  );

  const emptyMessage = (
    <FormattedMessage
      id='empty_column.custom_emoji_mutes'
      defaultMessage='You have not muted any custom emoji yet.'
    />
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='smile-o'
        iconComponent={MoodIcon}
        title={intl.formatMessage(messages.heading)}
        scrollTopOnClick
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
        <label className='custom-emoji-mute__checkbox'>
          <input
            type='checkbox'
            checked={rejectReactions}
            onChange={handleRejectReactionsChange}
          />
          <FormattedMessage
            id='custom_emoji_mutes.reject_reactions'
            defaultMessage='Also refuse emoji reactions that use these emoji'
          />
        </label>
        <label className='custom-emoji-mute__checkbox'>
          <input
            type='checkbox'
            checked={hideInPicker}
            onChange={handleHideInPickerChange}
          />
          <FormattedMessage
            id='custom_emoji_mutes.hide_in_picker'
            defaultMessage='Also hide these emoji in the emoji picker'
          />
        </label>
      </form>

      <div className='custom-emoji-mute__settings'>
        <label className='custom-emoji-mute__checkbox'>
          <input
            type='checkbox'
            checked={hidden}
            onChange={handleHiddenChange}
          />
          <FormattedMessage
            id='custom_emoji_mutes.hide_completely'
            defaultMessage='Hide muted emoji completely (show an empty box instead of translucent text)'
          />
        </label>
      </div>

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
            onToggleReject={handleToggleReject}
            onToggleHide={handleToggleHide}
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
