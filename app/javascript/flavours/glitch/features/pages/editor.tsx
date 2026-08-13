import { useEffect, useState, useCallback } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { useParams } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import {
  apiGetPage,
  apiGetPageSeries,
  apiSetBookletMainPage,
  apiUnsetBookletMainPage,
  apiCreatePage,
  apiUpdatePage,
} from 'flavours/glitch/api/pages';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';
import type {
  ApiPageBlock,
  ApiPageBlockType,
  ApiPageFont,
  ApiPageSeriesJSON,
  ApiPageVisibility,
} from 'flavours/glitch/api_types/pages';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import {
  TextInputField,
  TextAreaField,
  SelectField,
  CheckboxField,
} from 'flavours/glitch/components/form_fields';
import { useAppHistory } from 'flavours/glitch/components/router';
import {
  domain,
  isServerPageBlogViewPath,
  me,
} from 'flavours/glitch/initial_state';
import { useAppSelector } from 'flavours/glitch/store';

import { BlockAddButtons } from './components/block_add_buttons';
import { EditorBlock } from './components/editor_block';
import type { PageBlockPatch } from './components/editor_block';
import { ImageUploadField } from './components/image_upload_field';
import {
  createBlock,
  updateBlockInTree,
  removeBlockFromTree,
  moveBlockInTree,
} from './util/blocks';

const messages = defineMessages({
  newHeading: { id: 'pages.new', defaultMessage: 'New page' },
  editHeading: { id: 'pages.edit', defaultMessage: 'Edit page' },
  title: { id: 'pages.field.title', defaultMessage: 'Title' },
  name: { id: 'pages.field.name', defaultMessage: 'Display address' },
  addressHint: {
    id: 'pages.field.address_hint',
    defaultMessage: 'You will be able to access it at: {url}',
  },
  summary: { id: 'pages.field.summary', defaultMessage: 'Summary' },
  booklet: { id: 'pages.field.booklet', defaultMessage: 'Booklet' },
  bookletNone: { id: 'pages.booklet.none', defaultMessage: 'No Booklet' },
  bookletPosition: {
    id: 'pages.field.booklet_position',
    defaultMessage: 'Order in Booklet',
  },
  bookletPositionHint: {
    id: 'pages.field.booklet_position_hint',
    defaultMessage: 'Lower numbers appear first.',
  },
  bookletMain: {
    id: 'pages.field.booklet_main',
    defaultMessage: 'Use as the representative page for this Booklet',
  },
  visibility: { id: 'pages.field.visibility', defaultMessage: 'Visibility' },
  visibilityPublic: {
    id: 'pages.visibility.public',
    defaultMessage: 'Public',
  },
  visibilityAuthenticated: {
    id: 'pages.visibility.authenticated',
    defaultMessage: 'Signed-in users only',
  },
  visibilityPassword: {
    id: 'pages.visibility.password',
    defaultMessage: 'Password protected',
  },
  visibilityPrivate: {
    id: 'pages.visibility.private',
    defaultMessage: 'Only me',
  },
  password: { id: 'pages.field.password', defaultMessage: 'Password' },
  passwordHint: {
    id: 'pages.field.password_hint',
    defaultMessage:
      'Use 8–72 characters. Leave blank to keep the current password.',
  },
  eyeCatching: {
    id: 'pages.field.eye_catching',
    defaultMessage: 'Header image',
  },
  font: { id: 'pages.field.font', defaultMessage: 'Font' },
  alignCenter: {
    id: 'pages.field.align_center',
    defaultMessage: 'Center align',
  },
  save: { id: 'pages.save', defaultMessage: 'Save' },
  titleRequired: {
    id: 'pages.title_required',
    defaultMessage: 'Enter a title of at least one character.',
  },
});

const TOP_LEVEL_TYPES: ApiPageBlockType[] = [
  'text',
  'section',
  'image',
  'note',
  'youtube',
];

const PageEditor: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const history = useAppHistory();
  const { id } = useParams<{ id?: string }>();
  const isEditing = !!id;
  const account = useAppSelector((state) =>
    me ? state.accounts.get(me) : undefined,
  );

  const [title, setTitle] = useState('');
  const [name, setName] = useState(() => Date.now().toString());
  const [summary, setSummary] = useState('');
  const [bookletId, setBookletId] = useState('');
  const [bookletOptions, setBookletOptions] = useState<ApiPageSeriesJSON[]>([]);
  const [bookletPosition, setBookletPosition] = useState(0);
  const [bookletMain, setBookletMain] = useState(false);
  const [visibility, setVisibility] = useState<ApiPageVisibility>('public');
  const [password, setPassword] = useState('');
  const [hasExistingPassword, setHasExistingPassword] = useState(false);
  const [font, setFont] = useState<ApiPageFont>('sans-serif');
  const [alignCenter, setAlignCenter] = useState(false);
  const [content, setContent] = useState<ApiPageBlock[]>([]);
  const [eyeCatching, setEyeCatching] = useState<ApiMediaAttachmentJSON | null>(
    null,
  );
  const [mediaCache, setMediaCache] = useState<
    Record<string, ApiMediaAttachmentJSON>
  >({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(false);
  const [titleError, setTitleError] = useState(false);
  const useBlogView = isServerPageBlogViewPath(window.location.pathname);

  useEffect(() => {
    document.documentElement.classList.toggle('page-blog-view', useBlogView);
    document.body.classList.toggle('page-blog-view', useBlogView);

    return () => {
      document.documentElement.classList.remove('page-blog-view');
      document.body.classList.remove('page-blog-view');
    };
  }, [useBlogView]);

  useEffect(() => {
    apiGetPageSeries()
      .then((booklets) => {
        setBookletOptions(booklets);
        return booklets;
      })
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    if (!id) {
      return;
    }

    apiGetPage(id)
      .then((page) => {
        setTitle(page.title);
        setName(page.name);
        setSummary(page.summary ?? '');
        setBookletId(page.booklet_id ?? '');
        setBookletPosition(page.booklet_position);
        setBookletMain(page.booklet_main);
        setVisibility(page.visibility);
        setHasExistingPassword(page.visibility === 'password');
        setFont(page.font);
        setAlignCenter(page.align_center);
        setContent(page.content);
        setEyeCatching(page.eye_catching_media_attachment);
        setMediaCache(
          Object.fromEntries(
            page.attached_media.map((media) => [media.id, media]),
          ),
        );
        return page;
      })
      .catch(() => undefined);
  }, [id]);

  const handleTitleChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setTitle(event.target.value);
      setTitleError(false);
    },
    [],
  );

  const handleNameChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setName(event.target.value);
    },
    [],
  );

  const handleSummaryChange = useCallback(
    (event: React.ChangeEvent<HTMLTextAreaElement>) => {
      setSummary(event.target.value);
    },
    [],
  );

  const handleBookletChange = useCallback(
    (event: React.ChangeEvent<HTMLSelectElement>) => {
      setBookletId(event.target.value);
    },
    [],
  );

  const handleBookletPositionChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setBookletPosition(
        Math.max(0, Number.parseInt(event.target.value, 10) || 0),
      );
    },
    [],
  );

  const handleBookletMainChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setBookletMain(event.target.checked);
    },
    [],
  );

  const handleVisibilityChange = useCallback(
    (event: React.ChangeEvent<HTMLSelectElement>) => {
      setVisibility(event.target.value as ApiPageVisibility);
    },
    [],
  );

  const handlePasswordChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setPassword(event.target.value);
    },
    [],
  );

  const handleFontChange = useCallback(
    (event: React.ChangeEvent<HTMLSelectElement>) => {
      setFont(event.target.value as ApiPageFont);
    },
    [],
  );

  const handleAlignChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setAlignCenter(event.target.checked);
    },
    [],
  );

  const handleMediaUploaded = useCallback((media: ApiMediaAttachmentJSON) => {
    setMediaCache((cache) => ({ ...cache, [media.id]: media }));
  }, []);

  const getMedia = useCallback(
    (fileId: string | null) => (fileId ? (mediaCache[fileId] ?? null) : null),
    [mediaCache],
  );

  const handleUpdate = useCallback((blockId: string, patch: PageBlockPatch) => {
    setContent((blocks) =>
      updateBlockInTree(blocks, blockId, (block) => ({ ...block, ...patch })),
    );
  }, []);

  const handleRemove = useCallback((blockId: string) => {
    setContent((blocks) => removeBlockFromTree(blocks, blockId));
  }, []);

  const handleMove = useCallback((blockId: string, delta: number) => {
    setContent((blocks) => moveBlockInTree(blocks, blockId, delta));
  }, []);

  const handleAddBlock = useCallback((type: ApiPageBlockType) => {
    setContent((blocks) => [...blocks, createBlock(type)]);
  }, []);

  const handleAddChild = useCallback(
    (parentId: string, type: ApiPageBlockType) => {
      setContent((blocks) =>
        updateBlockInTree(blocks, parentId, (parent) =>
          parent.type === 'section'
            ? { ...parent, children: [...parent.children, createBlock(type)] }
            : parent,
        ),
      );
    },
    [],
  );

  const trimmedTitle = title.trim();

  const handleSave = useCallback(() => {
    if (!trimmedTitle) {
      setTitleError(true);
      return;
    }

    setSaving(true);
    setError(false);
    setTitleError(false);

    const buildPayload = (selectedBookletId: string | null) => ({
      title: trimmedTitle,
      name,
      summary: summary || null,
      booklet_id: selectedBookletId,
      booklet_position: bookletPosition,
      visibility,
      ...(password ? { password } : {}),
      font,
      align_center: alignCenter,
      content,
      eye_catching_media_attachment_id: eyeCatching?.id ?? null,
    });
    Promise.resolve(bookletId || null)
      .then((selectedBookletId) =>
        isEditing
          ? apiUpdatePage(id, buildPayload(selectedBookletId))
          : apiCreatePage(buildPayload(selectedBookletId)),
      )
      .then((savedPage) => {
        if (!savedPage.booklet_id || savedPage.visibility !== 'public') {
          return savedPage;
        }
        if (bookletMain && !savedPage.booklet_main) {
          return apiSetBookletMainPage(savedPage.id);
        }
        if (!bookletMain && savedPage.booklet_main) {
          return apiUnsetBookletMainPage(savedPage.id);
        }
        return savedPage;
      })
      .then((page) => {
        if (
          isEditing &&
          history.location.state?.fromPageShow &&
          history.location.state.pageName === page.name
        ) {
          history.goBack();
        } else {
          history.replace(
            `/@${page.account.acct}/pages/${encodeURIComponent(page.name)}`,
          );
        }

        return page;
      })
      .catch(() => {
        setError(true);
        setSaving(false);
      });
  }, [
    isEditing,
    id,
    trimmedTitle,
    name,
    summary,
    bookletId,
    bookletPosition,
    bookletMain,
    visibility,
    password,
    font,
    alignCenter,
    content,
    eyeCatching,
    history,
  ]);

  const heading = intl.formatMessage(
    isEditing ? messages.editHeading : messages.newHeading,
  );
  const pageUrl = `https://${domain}/@${account?.username ?? ''}/pages/${name}`;

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
        <div className='page-editor simple_form app-form'>
          <div className='fields-group'>
            <TextInputField
              id='page_title'
              required
              maxLength={256}
              label={intl.formatMessage(messages.title)}
              status={
                titleError
                  ? {
                      variant: 'error',
                      message: intl.formatMessage(messages.titleRequired),
                    }
                  : undefined
              }
              value={title}
              onChange={handleTitleChange}
            />
          </div>

          <div className='fields-group'>
            <TextInputField
              id='page_name'
              required
              maxLength={256}
              label={intl.formatMessage(messages.name)}
              hint={intl.formatMessage(messages.addressHint, {
                url: pageUrl,
              })}
              value={name}
              onChange={handleNameChange}
            />
          </div>

          <div className='fields-group'>
            <TextAreaField
              id='page_summary'
              maxLength={256}
              label={intl.formatMessage(messages.summary)}
              value={summary}
              onChange={handleSummaryChange}
            />
          </div>

          <div className='fields-group'>
            <SelectField
              id='page_visibility'
              label={intl.formatMessage(messages.visibility)}
              value={visibility}
              onChange={handleVisibilityChange}
            >
              <option value='public'>
                {intl.formatMessage(messages.visibilityPublic)}
              </option>
              <option value='authenticated'>
                {intl.formatMessage(messages.visibilityAuthenticated)}
              </option>
              <option value='password'>
                {intl.formatMessage(messages.visibilityPassword)}
              </option>
              <option value='private'>
                {intl.formatMessage(messages.visibilityPrivate)}
              </option>
            </SelectField>
          </div>

          <div className='fields-group fields-group-booklet'>
            <SelectField
              id='page_booklet'
              label={intl.formatMessage(messages.booklet)}
              value={bookletId}
              onChange={handleBookletChange}
            >
              <option value=''>
                {intl.formatMessage(messages.bookletNone)}
              </option>
              {bookletOptions.map((booklet) => (
                <option key={booklet.id} value={booklet.id}>
                  {booklet.title}
                </option>
              ))}
            </SelectField>

            {bookletId && (
              <>
                <TextInputField
                  id='page_booklet_position'
                  type='number'
                  min={0}
                  max={1000000}
                  label={intl.formatMessage(messages.bookletPosition)}
                  hint={intl.formatMessage(messages.bookletPositionHint)}
                  value={bookletPosition.toString()}
                  onChange={handleBookletPositionChange}
                />
                {visibility === 'public' && (
                  <CheckboxField
                    label={intl.formatMessage(messages.bookletMain)}
                    checked={bookletMain}
                    onChange={handleBookletMainChange}
                    wrapperClassName='page-editor__booklet-main'
                  />
                )}
              </>
            )}
          </div>

          {visibility === 'password' && (
            <div className='fields-group'>
              <TextInputField
                id='page_password'
                type='password'
                minLength={8}
                maxLength={72}
                required={!hasExistingPassword}
                autoComplete='new-password'
                label={intl.formatMessage(messages.password)}
                hint={intl.formatMessage(messages.passwordHint)}
                value={password}
                onChange={handlePasswordChange}
              />
            </div>
          )}

          <div className='fields-group'>
            <span className='page-editor__label'>
              {intl.formatMessage(messages.eyeCatching)}
            </span>
            <ImageUploadField value={eyeCatching} onChange={setEyeCatching} />
          </div>

          <div className='fields-group'>
            <SelectField
              id='page_font'
              label={intl.formatMessage(messages.font)}
              value={font}
              onChange={handleFontChange}
            >
              <option value='sans-serif'>Sans-serif</option>
              <option value='serif'>Serif</option>
            </SelectField>
          </div>

          <div className='fields-group'>
            <CheckboxField
              id='page_align_center'
              label={intl.formatMessage(messages.alignCenter)}
              checked={alignCenter}
              onChange={handleAlignChange}
            />
          </div>

          <div className='page-editor__blocks'>
            {content.map((block) => (
              <EditorBlock
                key={block.id}
                block={block}
                depth={0}
                onUpdate={handleUpdate}
                onRemove={handleRemove}
                onMove={handleMove}
                onAddChild={handleAddChild}
                onMediaUploaded={handleMediaUploaded}
                getMedia={getMedia}
              />
            ))}
          </div>

          <BlockAddButtons types={TOP_LEVEL_TYPES} onAdd={handleAddBlock} />

          {error && (
            <div className='page-editor__error'>
              <FormattedMessage
                id='pages.save_error'
                defaultMessage='Could not save the page. Check the title and slug.'
              />
            </div>
          )}

          <div className='page-editor__actions'>
            <button
              type='button'
              className='button'
              disabled={saving}
              onClick={handleSave}
            >
              {intl.formatMessage(messages.save)}
            </button>
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

// eslint-disable-next-line import/no-default-export
export default PageEditor;
