import { defineMessages, useIntl } from 'react-intl';
import { useDispatch } from 'react-redux';

import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import { deleteStatusDraft, setComposeToStatusDraft } from 'flavours/glitch/actions/status_drafts';
import { Icon } from 'flavours/glitch/components/icon';
import MediaGallery from 'flavours/glitch/components/media_gallery';
import { RelativeTimestamp } from 'flavours/glitch/components/relative_timestamp';

const messages = defineMessages({
  edit: { id: 'status_draft.edit', defaultMessage: 'Continue editing' },
  delete: { id: 'status_draft.delete', defaultMessage: 'Delete' },
  deleteConfirm: { id: 'status_draft.delete_confirm', defaultMessage: 'Delete this draft?' },
});

const escapeHtml = (text) => {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
};

export const StatusDraftCard = ({ draft }) => {
  const intl = useIntl();
  const dispatch = useDispatch();
  const params = draft.get('params');
  const media = draft.get('media_attachments');
  const text = params.get('status') || '';
  const spoiler = params.get('spoiler_text') || '';

  const handleDelete = () => {
    if (window.confirm(intl.formatMessage(messages.deleteConfirm))) {
      dispatch(deleteStatusDraft(draft.get('id')));
    }
  };

  const handleOpenMedia = (selectedMedia, index, lang) => {
    dispatch(openModal({
      modalType: 'MEDIA',
      modalProps: { media: selectedMedia, index, lang },
    }));
  };

  return (
    <div className='status status-wrapper scheduled-status-card'>
      <div className='scheduled-status-card__meta'>
        <RelativeTimestamp timestamp={draft.get('updated_at')} />
      </div>
      <div className='status__content'>
        {spoiler && <p className='status__content__spoiler-text'>{spoiler}</p>}
        <div
          className='status__content__text status__content__text--plain status__content__text--visible'
          dangerouslySetInnerHTML={{ __html: escapeHtml(text).replace(/\n/g, '<br />') }}
        />
        {media?.size > 0 && (
          <MediaGallery
            media={media}
            sensitive={params.get('sensitive')}
            lang={params.get('language')}
            onOpenMedia={handleOpenMedia}
          />
        )}
      </div>
      <div className='status__action-bar scheduled-status-card__actions'>
        <button type='button' className='icon-button' onClick={() => dispatch(setComposeToStatusDraft(draft))} title={intl.formatMessage(messages.edit)}>
          <Icon id='edit' icon={EditIcon} />
        </button>
        <button type='button' className='icon-button' onClick={handleDelete} title={intl.formatMessage(messages.delete)}>
          <Icon id='delete' icon={DeleteIcon} />
        </button>
      </div>
    </div>
  );
};
