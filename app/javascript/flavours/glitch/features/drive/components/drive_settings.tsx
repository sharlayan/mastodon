import { useCallback, useEffect, useState } from 'react';

import { FormattedMessage, defineMessages } from 'react-intl';

import { showAlert } from 'flavours/glitch/actions/alerts';
import {
  apiGetDriveSettings,
  apiUpdateDriveSettings,
} from 'flavours/glitch/api/drive';
import type {
  ApiDriveFolderJSON,
  ApiDriveSettingsJSON,
} from 'flavours/glitch/api_types/drive';
import {
  CheckboxField,
  FormStack,
  SelectField,
} from 'flavours/glitch/components/form_fields';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { useAppDispatch } from 'flavours/glitch/store';

const messages = defineMessages({
  saved: {
    id: 'drive.settings.saved',
    defaultMessage: 'Drive settings saved.',
  },
});

const DEFAULT_SETTINGS: ApiDriveSettingsJSON = {
  keep_original_filename: true,
  default_folder_id: null,
  upload_original_image: true,
};

export const DriveSettings: React.FC<{
  folders: ApiDriveFolderJSON[];
  onError: (error: unknown) => void;
}> = ({ folders, onError }) => {
  const dispatch = useAppDispatch();
  const [settings, setSettings] =
    useState<ApiDriveSettingsJSON>(DEFAULT_SETTINGS);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let cancelled = false;

    apiGetDriveSettings()
      .then((data) => {
        if (!cancelled) setSettings(data);
        return data;
      })
      .catch(onError)
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [onError]);

  const handleCheckbox = useCallback(
    (key: 'keep_original_filename' | 'upload_original_image') =>
      ({ target: { checked } }: React.ChangeEvent<HTMLInputElement>) => {
        setSettings((current) => ({ ...current, [key]: checked }));
      },
    [],
  );

  const handleFolderChange = useCallback(
    ({ target: { value } }: React.ChangeEvent<HTMLSelectElement>) => {
      setSettings((current) => ({
        ...current,
        default_folder_id: value || null,
      }));
    },
    [],
  );

  const handleSubmit = useCallback(
    (event: React.SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      setSaving(true);

      apiUpdateDriveSettings(settings)
        .then((data) => {
          setSettings(data);
          dispatch(showAlert({ message: messages.saved }));
          return data;
        })
        .catch(onError)
        .finally(() => {
          setSaving(false);
        });
    },
    [dispatch, onError, settings],
  );

  if (loading) return <LoadingIndicator />;

  return (
    <form className='drive__settings' onSubmit={handleSubmit}>
      <h3>
        <FormattedMessage id='drive.settings' defaultMessage='Drive settings' />
      </h3>

      <FormStack>
        <CheckboxField
          id='drive_keep_original_filename'
          label={
            <FormattedMessage
              id='drive.settings.keep_original_filename'
              defaultMessage='Keep original file names when uploading'
            />
          }
          hint={
            <FormattedMessage
              id='drive.settings.keep_original_filename_hint'
              defaultMessage='Save uploaded files with their original names.'
            />
          }
          checked={settings.keep_original_filename}
          onChange={handleCheckbox('keep_original_filename')}
        />

        <SelectField
          id='drive_default_folder_id'
          label={
            <FormattedMessage
              id='drive.settings.default_folder'
              defaultMessage='Default upload location'
            />
          }
          hint={
            <FormattedMessage
              id='drive.settings.default_folder_hint'
              defaultMessage='Select the folder to use for future automatic Drive uploads.'
            />
          }
          value={settings.default_folder_id ?? ''}
          onChange={handleFolderChange}
        >
          <option value=''>
            <FormattedMessage id='drive.root' defaultMessage='Drive' />
          </option>
          {folders.map((folder) => (
            <option key={folder.id} value={folder.id}>
              {folder.name}
            </option>
          ))}
        </SelectField>

        <CheckboxField
          id='drive_upload_original_image'
          label={
            <FormattedMessage
              id='drive.settings.upload_original_image'
              defaultMessage='Upload images at their original quality'
            />
          }
          hint={
            <FormattedMessage
              id='drive.settings.upload_original_image_hint'
              defaultMessage='When turned off, uploaded images are compressed to WebP to save space. Applies to new uploads only.'
            />
          }
          checked={settings.upload_original_image}
          onChange={handleCheckbox('upload_original_image')}
        />
      </FormStack>

      <button className='button' type='submit' disabled={saving}>
        <FormattedMessage
          id='drive.settings.save'
          defaultMessage='Save changes'
        />
      </button>
    </form>
  );
};
