import { useCallback, useId, useState } from 'react';

import { FormattedMessage, defineMessages, useIntl } from 'react-intl';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings.svg?react';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { NavigationFocusTarget } from 'flavours/glitch/components/navigation_focus_target';

import { useDrive } from '../use_drive';
import { useDrivePreview } from '../use_drive_preview';

import { DriveBrowser } from './drive_browser';
import { DriveSettings } from './drive_settings';

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
  settings: { id: 'drive.settings', defaultMessage: 'Drive settings' },
});

export const DriveManagerModal: React.FC<{ onClose: () => void }> = ({
  onClose,
}) => {
  const intl = useIntl();
  const titleId = useId();
  const drive = useDrive();
  const handleSelectFile = useDrivePreview(drive.files);
  const [showSettings, setShowSettings] = useState(false);

  const handleToggleSettings = useCallback(() => {
    setShowSettings((value) => !value);
  }, []);

  return (
    <div
      className='modal-root__modal dialog-modal drive-modal drive-modal--manager'
      role='dialog'
      aria-labelledby={titleId}
    >
      <div className='dialog-modal__header'>
        <div className='drive-modal__header-actions'>
          <IconButton
            title={intl.formatMessage(messages.settings)}
            icon='cog'
            iconComponent={SettingsIcon}
            active={showSettings}
            expanded={showSettings}
            onClick={handleToggleSettings}
          />

          <IconButton
            className='dialog-modal__header__close'
            title={intl.formatMessage(messages.close)}
            icon='times'
            iconComponent={CloseIcon}
            onClick={onClose}
          />
        </div>

        <NavigationFocusTarget
          as='h1'
          id={titleId}
          className='dialog-modal__header__title'
        >
          <FormattedMessage id='column.drive' defaultMessage='Drive' />
        </NavigationFocusTarget>
      </div>

      <div className='dialog-modal__content'>
        {showSettings && (
          <DriveSettings folders={drive.folders} onError={drive.onError} />
        )}

        <DriveBrowser
          drive={drive}
          manageable
          onSelectFile={handleSelectFile}
        />
      </div>
    </div>
  );
};
