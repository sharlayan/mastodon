import PropTypes from 'prop-types';
import { useCallback, useLayoutEffect, useRef } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { List as ImmutableList } from 'immutable';
import { useDispatch, useSelector } from 'react-redux';
import Textarea from 'react-textarea-autosize';
import { length } from 'stringz';

import AddPhotoAlternateIcon from '@/material-icons/400-24px/add_photo_alternate.svg?react';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import ReplyIcon from '@/material-icons/400-24px/reply.svg?react';
import WarningIcon from '@/material-icons/400-24px/warning.svg?react';
import {
  changeDirectCompose,
  changeDirectComposeSpoiler,
  toggleDirectComposeSpoiler,
  submitDirectMessage,
  uploadDirectMedia,
  removeDirectMedia,
  clearDirectReplyTo,
} from 'flavours/glitch/actions/direct_compose';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { CharacterCounter } from 'flavours/glitch/features/compose/components/character_counter';
import EmojiPickerDropdown from 'flavours/glitch/features/compose/containers/emoji_picker_dropdown_container';
import { UploadProgress } from 'flavours/glitch/features/compose/components/upload_progress';
import { countableText } from 'flavours/glitch/features/compose/util/counter';
import { makeGetStatus } from 'flavours/glitch/selectors';

const messages = defineMessages({
  placeholder: { id: 'direct_composer.placeholder', defaultMessage: 'Send a message…' },
  send: { id: 'direct_composer.send', defaultMessage: 'Send' },
  upload: { id: 'direct_composer.upload', defaultMessage: 'Add image' },
  removeMedia: { id: 'direct_composer.remove_media', defaultMessage: 'Remove' },
  cancelReply: { id: 'direct_composer.cancel_reply', defaultMessage: 'Cancel reply' },
  spoiler: { id: 'direct_composer.spoiler', defaultMessage: 'Add content warning' },
  spoilerPlaceholder: { id: 'direct_composer.spoiler_placeholder', defaultMessage: 'Content warning (optional)' },
});

const getStatus = makeGetStatus();

export const DirectComposer = ({ conversationId, inReplyToId, recipientIds }) => {
  const intl = useIntl();
  const dispatch = useDispatch();
  const fileRef = useRef(null);
  const inputRef = useRef(null);
  const textareaRef = useRef(null);
  const rowRef = useRef(null);

  const text         = useSelector(state => state.getIn(['direct_compose', conversationId, 'text'], ''));
  const spoiler      = useSelector(state => state.getIn(['direct_compose', conversationId, 'spoiler'], false));
  const spoilerText  = useSelector(state => state.getIn(['direct_compose', conversationId, 'spoiler_text'], ''));
  const media        = useSelector(state => state.getIn(['direct_compose', conversationId, 'media'], ImmutableList()));
  const isUploading  = useSelector(state => state.getIn(['direct_compose', conversationId, 'is_uploading'], false));
  const isSubmitting = useSelector(state => state.getIn(['direct_compose', conversationId, 'is_submitting'], false));
  const progress     = useSelector(state => state.getIn(['direct_compose', conversationId, 'progress'], 0));
  const maxChars     = useSelector(state => state.getIn(['server', 'server', 'item', 'configuration', 'statuses', 'max_characters'], 500));

  const replyOverrideId   = useSelector(state => state.getIn(['direct_compose', conversationId, 'in_reply_to_id'], null));
  const replyStatus       = useSelector(state => replyOverrideId ? getStatus(state, { id: replyOverrideId }) : null);
  const effectiveReplyId  = replyOverrideId || inReplyToId;

  const countedText = `${spoiler ? spoilerText : ''}${countableText(text)}`;
  const canSubmit = !isSubmitting && length(countedText) <= maxChars && (text.trim().length > 0 || media.size > 0);

  useLayoutEffect(() => {
    const textarea = textareaRef.current;
    const row = rowRef.current;

    if (!textarea || !row) {
      return;
    }

    let tallest = 0;

    for (const child of row.children) {
      if (child === inputRef.current) {
        continue;
      }

      tallest = Math.max(tallest, child.offsetHeight);
    }

    textarea.style.minHeight = tallest > 0 ? `${tallest}px` : '';
  });

  const handleChange = useCallback(e => {
    dispatch(changeDirectCompose(conversationId, e.target.value));
  }, [dispatch, conversationId]);

  const handleSpoilerChange = useCallback(e => {
    dispatch(changeDirectComposeSpoiler(conversationId, e.target.value));
  }, [dispatch, conversationId]);

  const handleToggleSpoiler = useCallback(() => {
    dispatch(toggleDirectComposeSpoiler(conversationId));
  }, [dispatch, conversationId]);

  const handleEmojiPick = useCallback(data => {
    const textarea = textareaRef.current;
    const position = textarea ? textarea.selectionStart : text.length;
    const needsSpace = position > 0 && !(/\s/).test(text[position - 1]);
    const emoji = needsSpace ? ` ${data.native}` : data.native;
    const newText = `${text.slice(0, position)}${emoji} ${text.slice(position)}`;

    dispatch(changeDirectCompose(conversationId, newText));

    requestAnimationFrame(() => {
      const caret = position + emoji.length + 1;
      if (textareaRef.current) {
        textareaRef.current.focus();
        textareaRef.current.setSelectionRange(caret, caret);
      }
    });
  }, [dispatch, conversationId, text]);

  const handleSubmit = useCallback(() => {
    dispatch(submitDirectMessage(conversationId, { inReplyToId: effectiveReplyId, recipientIds }));
  }, [dispatch, conversationId, effectiveReplyId, recipientIds]);

  const handleCancelReply = useCallback(() => {
    dispatch(clearDirectReplyTo(conversationId));
  }, [dispatch, conversationId]);

  const handleKeyDown = useCallback(e => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      handleSubmit();
    }
  }, [handleSubmit]);

  const handlePaste = useCallback(e => {
    const files = e.clipboardData?.files;

    if (files && files.length > 0) {
      dispatch(uploadDirectMedia(conversationId, files));
      e.preventDefault();
    }
  }, [dispatch, conversationId]);

  const handleUploadClick = useCallback(() => {
    fileRef.current?.click();
  }, []);

  const handleFileChange = useCallback(e => {
    if (e.target.files?.length > 0) {
      dispatch(uploadDirectMedia(conversationId, e.target.files));
    }

    e.target.value = '';
  }, [dispatch, conversationId]);

  const handleRemoveMedia = useCallback(id => {
    dispatch(removeDirectMedia(conversationId, id));
  }, [dispatch, conversationId]);

  return (
    <div className='direct-composer'>
      {replyStatus && (
        <div className='direct-composer__reply'>
          <Icon id='reply' icon={ReplyIcon} className='direct-composer__reply__icon' />
          <span className='direct-composer__reply__label'>
            <FormattedMessage
              id='direct_composer.replying_to'
              defaultMessage='Replying to {name}'
              values={{ name: <DisplayName account={replyStatus.get('account')} variant='simple' /> }}
            />
          </span>
          <IconButton
            className='direct-composer__reply__cancel'
            title={intl.formatMessage(messages.cancelReply)}
            icon='times'
            iconComponent={CloseIcon}
            onClick={handleCancelReply}
          />
        </div>
      )}

      {spoiler && (
        <input
          className='direct-composer__spoiler'
          placeholder={intl.formatMessage(messages.spoilerPlaceholder)}
          value={spoilerText}
          onChange={handleSpoilerChange}
          disabled={isSubmitting}
        />
      )}

      {media.size > 0 && (
        <div className='direct-composer__media'>
          {media.map(item => (
            <div className='direct-composer__media__item' key={item.get('id')}>
              <img src={item.get('preview_url')} alt='' />
              <IconButton
                className='direct-composer__media__remove'
                title={intl.formatMessage(messages.removeMedia)}
                icon='times'
                iconComponent={CloseIcon}
                onClick={() => handleRemoveMedia(item.get('id'))}
              />
            </div>
          ))}
        </div>
      )}

      <UploadProgress active={isUploading} progress={progress} />

      <div className='direct-composer__row' ref={rowRef}>
        <input
          ref={fileRef}
          type='file'
          accept='image/*,video/*'
          multiple={false}
          style={{ display: 'none' }}
          onChange={handleFileChange}
        />

        <div className='direct-composer__input' ref={inputRef}>
          <Textarea
            ref={textareaRef}
            className='direct-composer__textarea'
            placeholder={intl.formatMessage(messages.placeholder)}
            value={text}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            onPaste={handlePaste}
            minRows={1}
            maxRows={5}
            disabled={isSubmitting}
          />
          <div className='direct-composer__counter'>
            <CharacterCounter max={maxChars} text={countedText} />
          </div>
        </div>

        <button
          type='button'
          className='direct-composer__send'
          onClick={handleSubmit}
          disabled={!canSubmit}
        >
          {intl.formatMessage(messages.send)}
        </button>

        <IconButton
          className='direct-composer__button'
          title={intl.formatMessage(messages.upload)}
          icon='camera'
          iconComponent={AddPhotoAlternateIcon}
          onClick={handleUploadClick}
          disabled={isUploading}
        />

        <div className='direct-composer__emoji'>
          <EmojiPickerDropdown onPickEmoji={handleEmojiPick} />
        </div>

        <IconButton
          className='direct-composer__button'
          title={intl.formatMessage(messages.spoiler)}
          icon='warning'
          iconComponent={WarningIcon}
          onClick={handleToggleSpoiler}
          active={spoiler}
          disabled={isSubmitting}
        />
      </div>
    </div>
  );
};

DirectComposer.propTypes = {
  conversationId: PropTypes.string.isRequired,
  inReplyToId: PropTypes.string,
  recipientIds: PropTypes.array,
};
