import PropTypes from 'prop-types';
import { useCallback, useRef } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import classNames from 'classnames';

import { List as ImmutableList } from 'immutable';
import { useDispatch, useSelector } from 'react-redux';

import AddPhotoAlternateIcon from '@/material-icons/400-24px/add_photo_alternate.svg?react';
import ArrowUpwardIcon from '@/material-icons/400-24px/arrow_upward.svg?react';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import ReplyIcon from '@/material-icons/400-24px/reply.svg?react';
import {
  changeDirectCompose,
  submitDirectMessage,
  uploadDirectMedia,
  removeDirectMedia,
  clearDirectReplyTo,
} from 'flavours/glitch/actions/direct_compose';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { UploadProgress } from 'flavours/glitch/features/compose/components/upload_progress';
import { makeGetStatus } from 'flavours/glitch/selectors';

const messages = defineMessages({
  placeholder: { id: 'direct_composer.placeholder', defaultMessage: 'Send a message…' },
  send: { id: 'direct_composer.send', defaultMessage: 'Send' },
  upload: { id: 'direct_composer.upload', defaultMessage: 'Add image' },
  removeMedia: { id: 'direct_composer.remove_media', defaultMessage: 'Remove' },
  cancelReply: { id: 'direct_composer.cancel_reply', defaultMessage: 'Cancel reply' },
});

const getStatus = makeGetStatus();

export const DirectComposer = ({ conversationId, inReplyToId, recipientIds }) => {
  const intl = useIntl();
  const dispatch = useDispatch();
  const fileRef = useRef(null);

  const text         = useSelector(state => state.getIn(['direct_compose', conversationId, 'text'], ''));
  const media        = useSelector(state => state.getIn(['direct_compose', conversationId, 'media'], ImmutableList()));
  const isUploading  = useSelector(state => state.getIn(['direct_compose', conversationId, 'is_uploading'], false));
  const isSubmitting = useSelector(state => state.getIn(['direct_compose', conversationId, 'is_submitting'], false));
  const progress     = useSelector(state => state.getIn(['direct_compose', conversationId, 'progress'], 0));

  const replyOverrideId   = useSelector(state => state.getIn(['direct_compose', conversationId, 'in_reply_to_id'], null));
  const replyStatus       = useSelector(state => replyOverrideId ? getStatus(state, { id: replyOverrideId }) : null);
  const effectiveReplyId  = replyOverrideId || inReplyToId;

  const canSubmit = !isSubmitting && (text.trim().length > 0 || media.size > 0);

  const handleChange = useCallback(e => {
    dispatch(changeDirectCompose(conversationId, e.target.value));
  }, [dispatch, conversationId]);

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

      <div className='direct-composer__row'>
        <input
          ref={fileRef}
          type='file'
          accept='image/*,video/*'
          multiple={false}
          style={{ display: 'none' }}
          onChange={handleFileChange}
        />

        <IconButton
          className='direct-composer__button'
          title={intl.formatMessage(messages.upload)}
          icon='camera'
          iconComponent={AddPhotoAlternateIcon}
          onClick={handleUploadClick}
          disabled={isUploading}
        />

        <textarea
          className='direct-composer__textarea'
          placeholder={intl.formatMessage(messages.placeholder)}
          value={text}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          rows={1}
          disabled={isSubmitting}
        />

        <IconButton
          className={classNames('direct-composer__button', 'direct-composer__send')}
          title={intl.formatMessage(messages.send)}
          icon='paper-plane'
          iconComponent={ArrowUpwardIcon}
          onClick={handleSubmit}
          disabled={!canSubmit}
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
