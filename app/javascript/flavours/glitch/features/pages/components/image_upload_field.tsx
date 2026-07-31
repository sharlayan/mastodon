import { useState, useCallback, useRef } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { showAlertForError } from 'flavours/glitch/actions/alerts';
import { openModal } from 'flavours/glitch/actions/modal';
import { apiAttachDriveFile } from 'flavours/glitch/api/drive';
import { apiUploadPageMedia } from 'flavours/glitch/api/pages';
import type { ApiDriveFileJSON } from 'flavours/glitch/api_types/drive';
import type { ApiMediaAttachmentJSON } from 'flavours/glitch/api_types/media_attachments';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { driveEnabled } from 'flavours/glitch/initial_state';
import { useAppDispatch } from 'flavours/glitch/store';

const messages = defineMessages({
  cropTitle: {
    id: 'pages.booklet.crop_cover',
    defaultMessage: 'Crop Booklet cover',
  },
});

export const ImageUploadField: React.FC<{
  value: ApiMediaAttachmentJSON | null;
  onChange: (media: ApiMediaAttachmentJSON | null) => void;
}> = ({ value, onChange }) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const inputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  const openCropModal = useCallback(
    (src: string, fileName: string) => {
      dispatch(
        openModal({
          modalType: 'BOOKLET_COVER_CROP',
          modalProps: {
            src,
            title: intl.formatMessage(messages.cropTitle),
            onComplete: async (blob: Blob) => {
              setUploading(true);
              const uploadName = fileName.replace(/\.[^.]+$/, '') + '.png';
              const file = new File([blob], uploadName, {
                type: blob.type || 'image/png',
              });

              try {
                const media = await apiUploadPageMedia(file);
                onChange(media);
              } finally {
                setUploading(false);
              }
            },
            onError: (error: unknown) => {
              dispatch(showAlertForError(error));
            },
          },
        }),
      );
    },
    [dispatch, intl, onChange],
  );

  const handleFileChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const file = event.target.files?.[0];

      if (!file) {
        return;
      }

      const reader = new FileReader();
      reader.addEventListener('load', () => {
        if (typeof reader.result === 'string') {
          openCropModal(reader.result, file.name);
        }
      });
      reader.readAsDataURL(file);

      event.target.value = '';
    },
    [openCropModal],
  );

  const handleBrowseClick = useCallback(() => {
    inputRef.current?.click();
  }, []);

  const handleDriveSelect = useCallback(
    async (file: ApiDriveFileJSON) => {
      setUploading(true);

      try {
        const media = await apiAttachDriveFile(file.id);
        onChange(media);
      } catch (error: unknown) {
        dispatch(showAlertForError(error));
        throw error;
      } finally {
        setUploading(false);
      }
    },
    [dispatch, onChange],
  );

  const handleDriveClick = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'DRIVE',
        modalProps: {
          accept: 'image/*',
          acceptedTypes: ['image', 'gifv'],
          onSelectFile: handleDriveSelect,
        },
      }),
    );
  }, [dispatch, handleDriveSelect]);

  const handleClear = useCallback(() => {
    onChange(null);

    if (inputRef.current) {
      inputRef.current.value = '';
    }
  }, [onChange]);

  return (
    <div className='page-editor__image-upload'>
      {value && (
        <img
          className='page-editor__image-upload__preview'
          src={value.preview_url || value.url}
          alt=''
        />
      )}

      {uploading ? (
        <LoadingIndicator />
      ) : (
        <div className='page-editor__image-upload__actions'>
          <button
            type='button'
            className='button button-secondary'
            onClick={handleBrowseClick}
          >
            <FormattedMessage
              id='pages.upload_image'
              defaultMessage='Upload image'
            />
          </button>

          {driveEnabled && (
            <button
              type='button'
              className='button button-secondary'
              onClick={handleDriveClick}
            >
              <FormattedMessage
                id='pages.use_drive_image'
                defaultMessage='Use image from Drive'
              />
            </button>
          )}

          {value && (
            <button
              type='button'
              className='button button-tertiary'
              onClick={handleClear}
            >
              <FormattedMessage
                id='pages.remove_image'
                defaultMessage='Remove'
              />
            </button>
          )}
        </div>
      )}

      <input
        ref={inputRef}
        type='file'
        accept='image/*'
        style={{ display: 'none' }}
        onChange={handleFileChange}
      />
    </div>
  );
};
