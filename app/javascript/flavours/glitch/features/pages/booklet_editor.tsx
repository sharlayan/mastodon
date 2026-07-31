import { useCallback, useEffect, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { useParams } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import {
  apiCreatePageSeries,
  apiGetPageSeries,
  apiUpdatePageSeries,
} from 'flavours/glitch/api/pages';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import {
  TextAreaField,
  TextInputField,
} from 'flavours/glitch/components/form_fields';
import { useAppHistory } from 'flavours/glitch/components/router';

import { ImageUploadField } from './components/image_upload_field';

const messages = defineMessages({
  newHeading: {
    id: 'pages.booklet.new',
    defaultMessage: 'Create Booklet',
  },
  editHeading: {
    id: 'pages.booklet.edit',
    defaultMessage: 'Edit Booklet',
  },
  title: { id: 'pages.field.series_title', defaultMessage: 'Booklet title' },
  description: {
    id: 'pages.field.series_description',
    defaultMessage: 'Booklet description',
  },
  cover: { id: 'pages.field.series_cover', defaultMessage: 'Booklet cover' },
  coverHint: {
    id: 'pages.field.series_cover_hint',
    defaultMessage: 'Crop to a 3:4 ratio, up to 600 × 800 px.',
  },
  preview: {
    id: 'pages.booklet.preview',
    defaultMessage: 'Preview',
  },
  save: { id: 'pages.save', defaultMessage: 'Save' },
  saveError: {
    id: 'pages.booklet.save_error',
    defaultMessage: 'Could not save the Booklet.',
  },
});

export const BookletEditor: React.FC<{ multiColumn?: boolean }> = ({
  multiColumn,
}) => {
  const intl = useIntl();
  const history = useAppHistory();
  const { id } = useParams<{ id?: string }>();
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [cover, setCover] = useState<ApiMediaAttachmentJSON | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(false);

  const handleTitleChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setTitle(event.target.value);
    },
    [],
  );

  const handleDescriptionChange = useCallback(
    (event: React.ChangeEvent<HTMLTextAreaElement>) => {
      setDescription(event.target.value);
    },
    [],
  );

  useEffect(() => {
    if (!id) return;

    void apiGetPageSeries().then((booklets) => {
      const booklet = booklets.find((item) => item.id === id);
      if (!booklet) return;
      setTitle(booklet.title);
      setDescription(booklet.description ?? '');
      setCover(booklet.cover_media_attachment);
    });
  }, [id]);

  const handleSave = useCallback(() => {
    if (!title.trim()) return;
    setSaving(true);
    setError(false);
    const payload = {
      title,
      description: description || null,
      cover_media_attachment_id: cover?.id ?? null,
    };
    const request = id
      ? apiUpdatePageSeries(id, payload)
      : apiCreatePageSeries(payload);
    void request
      .then(() => {
        history.replace('/pages');
      })
      .catch(() => {
        setSaving(false);
        setError(true);
      });
  }, [cover, description, history, id, title]);

  const heading = intl.formatMessage(
    id ? messages.editHeading : messages.newHeading,
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      className='page-editor-column'
      label={heading}
    >
      <ColumnHeader
        title={heading}
        icon='description'
        iconComponent={DescriptionIcon}
        multiColumn={multiColumn}
        showBackButton
      />
      <div className='scrollable'>
        <div className='page-editor'>
          <div className='fields-group'>
            <TextInputField
              id='booklet_title'
              required
              maxLength={100}
              label={intl.formatMessage(messages.title)}
              value={title}
              onChange={handleTitleChange}
            />
            <TextAreaField
              id='booklet_description'
              maxLength={500}
              label={intl.formatMessage(messages.description)}
              value={description}
              onChange={handleDescriptionChange}
            />
          </div>
          <div className='fields-group page-editor__booklet-cover'>
            <span className='page-editor__label'>
              {intl.formatMessage(messages.cover)}
            </span>
            <span className='page-editor__hint'>
              {intl.formatMessage(messages.coverHint)}
            </span>
            <ImageUploadField value={cover} onChange={setCover} />
          </div>
          <section
            className='page-editor__booklet-preview'
            aria-label={intl.formatMessage(messages.preview)}
          >
            <span className='page-editor__label'>
              {intl.formatMessage(messages.preview)}
            </span>
            <div className='page-editor__booklet-preview-card'>
              {cover ? (
                <img
                  className='page-editor__booklet-preview-cover'
                  src={cover.preview_url || cover.url}
                  alt=''
                />
              ) : (
                <span className='page-editor__booklet-preview-cover page-editor__booklet-preview-cover--empty' />
              )}
              <div className='page-editor__booklet-preview-details'>
                <strong className={title.trim() ? undefined : 'is-placeholder'}>
                  [{title.trim() || intl.formatMessage(messages.title)}]
                </strong>
                {description && <p>{description}</p>}
              </div>
            </div>
          </section>
          <div className='page-editor__actions'>
            <button
              type='button'
              className='button'
              disabled={saving || !title.trim()}
              onClick={handleSave}
            >
              {intl.formatMessage(messages.save)}
            </button>
            {error && (
              <p className='page-editor__error'>
                {intl.formatMessage(messages.saveError)}
              </p>
            )}
          </div>
        </div>
      </div>
      <Helmet>
        <title>{heading}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};
