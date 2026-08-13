import { useCallback, useState, useEffect } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { useParams, useHistory } from 'react-router-dom';

import { isFulfilled } from '@reduxjs/toolkit';

import { Helmet } from '@unhead/react/helmet';

import { NotSignedInIndicator } from '@/flavours/glitch/components/not_signed_in_indicator';
import { useIdentity } from '@/flavours/glitch/identity_context';
import NoteStackAddIcon from '@/material-icons/400-24px/note_stack_add.svg?react';
import { showAlert } from 'flavours/glitch/actions/alerts';
import {
  fetchClip,
  createClip,
  updateClip,
} from 'flavours/glitch/actions/clips';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import {
  TextInputField,
  TextAreaField,
  Toggle,
} from 'flavours/glitch/components/form_fields';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import type { Clip } from 'flavours/glitch/models/clip';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

const messages = defineMessages({
  edit: { id: 'column.edit_clip', defaultMessage: 'Edit clip' },
  create: { id: 'column.create_clip', defaultMessage: 'Create clip' },
  saved: { id: 'clips.saved', defaultMessage: 'Clip saved' },
  created: { id: 'clips.created', defaultMessage: 'Clip created' },
});

const NewClip: React.FC<{ clip?: Clip | null }> = ({ clip }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const history = useHistory();

  const {
    id,
    title: initialTitle = '',
    description: initialDescription = '',
    public: initialPublic = false,
  } = clip ?? {};

  const [title, setTitle] = useState(initialTitle);
  const [description, setDescription] = useState(initialDescription ?? '');
  const [isPublic, setIsPublic] = useState(initialPublic);
  const [submitting, setSubmitting] = useState(false);

  const handleTitleChange = useCallback(
    ({ target: { value } }: React.ChangeEvent<HTMLInputElement>) => {
      setTitle(value);
    },
    [setTitle],
  );

  const handleDescriptionChange = useCallback(
    ({ target: { value } }: React.ChangeEvent<HTMLTextAreaElement>) => {
      setDescription(value);
    },
    [setDescription],
  );

  const handlePublicChange = useCallback(
    ({ target: { checked } }: React.ChangeEvent<HTMLInputElement>) => {
      setIsPublic(checked);
    },
    [setIsPublic],
  );

  const isDirty = id
    ? title !== initialTitle ||
      description !== (initialDescription ?? '') ||
      isPublic !== initialPublic
    : true;
  const canSubmit = !submitting && isDirty && title.trim().length > 0;

  const handleSubmit = useCallback(
    (event: React.SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();

      if (!canSubmit) {
        return;
      }

      setSubmitting(true);

      if (id) {
        void dispatch(
          updateClip({ id, title, description, public: isPublic }),
        ).then((result) => {
          setSubmitting(false);

          if (isFulfilled(result)) {
            dispatch(
              showAlert({ message: intl.formatMessage(messages.saved) }),
            );
          }

          return '';
        });
      } else {
        void dispatch(
          createClip({ title, description, public: isPublic }),
        ).then((result) => {
          setSubmitting(false);

          if (isFulfilled(result)) {
            dispatch(
              showAlert({ message: intl.formatMessage(messages.created) }),
            );
            history.replace(`/clips/${result.payload.id}`);
          }

          return '';
        });
      }
    },
    [
      history,
      dispatch,
      intl,
      canSubmit,
      setSubmitting,
      id,
      title,
      description,
      isPublic,
    ],
  );

  return (
    <form className='simple_form app-form' onSubmit={handleSubmit}>
      <div className='fields-group'>
        <TextInputField
          required
          maxLength={128}
          label={
            <FormattedMessage id='clips.clip_name' defaultMessage='Clip name' />
          }
          value={title}
          onChange={handleTitleChange}
          id='clip_title'
        />
      </div>

      <div className='fields-group'>
        <TextAreaField
          maxLength={2048}
          label={
            <FormattedMessage
              id='clips.clip_description'
              defaultMessage='Description'
            />
          }
          value={description}
          onChange={handleDescriptionChange}
          id='clip_description'
        />
      </div>

      <div className='fields-group'>
        {/* eslint-disable-next-line jsx-a11y/label-has-associated-control */}
        <label className='app-form__toggle'>
          <div className='app-form__toggle__label'>
            <strong>
              <FormattedMessage
                id='clips.public'
                defaultMessage='Public clip'
              />
            </strong>
            <span className='hint'>
              <FormattedMessage
                id='clips.public_hint'
                defaultMessage='When enabled, anyone can view this clip. When disabled, only you can see it.'
              />
            </span>
          </div>

          <div className='app-form__toggle__toggle'>
            <div>
              <Toggle checked={isPublic} onChange={handlePublicChange} />
            </div>
          </div>
        </label>
      </div>

      <div className='actions'>
        <button className='button' type='submit' disabled={!canSubmit}>
          {submitting ? (
            <LoadingIndicator />
          ) : id ? (
            <FormattedMessage id='clips.save' defaultMessage='Save' />
          ) : (
            <FormattedMessage id='clips.create' defaultMessage='Create' />
          )}
        </button>
      </div>
    </form>
  );
};

const NewClipWrapper: React.FC<{
  multiColumn?: boolean;
}> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { signedIn } = useIdentity();
  const { id } = useParams<{ id?: string }>();
  const clip = useAppSelector((state) =>
    id ? state.clips.get(id) : undefined,
  );

  useEffect(() => {
    if (signedIn && id) {
      void dispatch(fetchClip({ id }));
    }
  }, [dispatch, signedIn, id]);

  const isLoading = id && !clip;

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(id ? messages.edit : messages.create)}
    >
      <ColumnHeader
        title={intl.formatMessage(id ? messages.edit : messages.create)}
        icon='note-stack-add'
        iconComponent={NoteStackAddIcon}
        multiColumn={multiColumn}
        showBackButton
      />

      <div className='scrollable'>
        {!signedIn ? (
          <NotSignedInIndicator />
        ) : isLoading ? (
          <LoadingIndicator />
        ) : (
          <NewClip clip={clip} />
        )}
      </div>

      <Helmet>
        <title>
          {intl.formatMessage(id ? messages.edit : messages.create)}
        </title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default NewClipWrapper;
