import { useCallback, useEffect, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { useParams } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';
import { isAxiosError } from 'axios';

import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import {
  apiCreatePageSeries,
  apiGetPageSeries,
  apiUpdatePageSeries,
} from 'flavours/glitch/api/pages';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import {
  SelectField,
  TextAreaField,
  TextInputField,
} from 'flavours/glitch/components/form_fields';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { useAppHistory } from 'flavours/glitch/components/router';
import { BundleColumnError } from 'flavours/glitch/features/ui/components/bundle_column_error';

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
  const [displayed, setDisplayed] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(false);
  const [loadedId, setLoadedId] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<{
    id: string;
    notFound: boolean;
  } | null>(null);
  const [loadAttempt, setLoadAttempt] = useState(0);

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

  const handleDisplayedChange = useCallback(
    (event: React.ChangeEvent<HTMLSelectElement>) => {
      setDisplayed(event.currentTarget.value === 'public');
    },
    [],
  );

  useEffect(() => {
    if (!id) return;

    let active = true;

    apiGetPageSeries()
      .then((booklets) => {
        if (!active) return booklets;

        const booklet = booklets.find((item) => item.id === id);

        if (!booklet) {
          setLoadError({ id, notFound: true });
          return booklets;
        }

        setTitle(booklet.title);
        setDescription(booklet.description ?? '');
        setCover(booklet.cover_media_attachment);
        setDisplayed(booklet.displayed);
        setLoadedId(id);
        return booklets;
      })
      .catch((loadFailure: unknown) => {
        if (!active) return;

        const status = isAxiosError(loadFailure)
          ? loadFailure.response?.status
          : undefined;
        setLoadError({ id, notFound: status === 404 || status === 410 });
      });

    return () => {
      active = false;
    };
  }, [id, loadAttempt]);

  const handleRetryLoad = useCallback(() => {
    setLoadError(null);
    setLoadAttempt((attempt) => attempt + 1);
  }, []);

  const loaded = !id || loadedId === id;

  const handleSave = useCallback(() => {
    if (!loaded || !title.trim()) return;
    setSaving(true);
    setError(false);
    const payload = {
      title,
      description: description || null,
      cover_media_attachment_id: cover?.id ?? null,
      displayed,
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
  }, [cover, description, displayed, history, id, loaded, title]);

  const heading = intl.formatMessage(
    id ? messages.editHeading : messages.newHeading,
  );

  if (id && loadError?.id === id) {
    return (
      <BundleColumnError
        multiColumn={multiColumn}
        errorType={loadError.notFound ? 'routing' : 'network'}
        onRetry={handleRetryLoad}
      />
    );
  }

  if (!loaded) {
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
        <LoadingIndicator />
        <Helmet>
          <title>{heading}</title>
          <meta name='robots' content='noindex' />
        </Helmet>
      </Column>
    );
  }

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
            <ImageUploadField value={cover} onChange={setCover} crop />
          </div>
          <div className='fields-group'>
            <SelectField
              id='booklet_displayed'
              label={intl.formatMessage({
                id: 'pages.field.booklet_displayed',
                defaultMessage: 'Showcase visibility',
              })}
              hint={intl.formatMessage({
                id: 'pages.field.booklet_displayed_hint',
                defaultMessage:
                  'Hidden Booklets remain visible from your profile.',
              })}
              value={displayed ? 'public' : 'private'}
              onChange={handleDisplayedChange}
            >
              <option value='public'>
                {intl.formatMessage({
                  id: 'pages.field.booklet_displayed.public',
                  defaultMessage: 'Public',
                })}
              </option>
              <option value='private'>
                {intl.formatMessage({
                  id: 'pages.field.booklet_displayed.private',
                  defaultMessage: 'Private',
                })}
              </option>
            </SelectField>
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
