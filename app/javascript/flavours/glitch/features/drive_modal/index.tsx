import { useCallback, useId, useState } from 'react';

import { FormattedMessage, useIntl, defineMessages } from 'react-intl';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import { attachDriveFile } from 'flavours/glitch/actions/compose';
import type { ApiDriveFileJSON } from 'flavours/glitch/api_types/drive';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import { NavigationFocusTarget } from 'flavours/glitch/components/navigation_focus_target';
import { DriveBrowser } from 'flavours/glitch/features/drive/components/drive_browser';
import { useDrive } from 'flavours/glitch/features/drive/use_drive';
import { useAppDispatch } from 'flavours/glitch/store';

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
});

export const DriveModal: React.FC<{
  onClose: () => void;
  onSelectFile?: (file: ApiDriveFileJSON) => void | Promise<void>;
  acceptedTypes?: ApiDriveFileJSON['type'][];
  accept?: string;
}> = ({ onClose, onSelectFile, acceptedTypes, accept }) => {
  const intl = useIntl();
  const titleId = useId();
  const dispatch = useAppDispatch();
  const drive = useDrive();
  const [selecting, setSelecting] = useState(false);

  const handleSelectFile = useCallback(
    (file: ApiDriveFileJSON) => {
      if (selecting) {
        return;
      }

      if (onSelectFile) {
        setSelecting(true);
        Promise.resolve(onSelectFile(file))
          .then(onClose)
          .catch(() => {
            setSelecting(false);
          });
        return;
      }

      dispatch(attachDriveFile(file.id, file.sensitive));
      onClose();
    },
    [dispatch, onClose, onSelectFile, selecting],
  );

  return (
    <div className='modal-root__modal dialog-modal drive-modal'>
      <div className='dialog-modal__header'>
        <IconButton
          className='dialog-modal__header__close'
          title={intl.formatMessage(messages.close)}
          icon='times'
          iconComponent={CloseIcon}
          onClick={onClose}
        />

        <NavigationFocusTarget
          as='h1'
          id={titleId}
          className='dialog-modal__header__title'
        >
          <FormattedMessage
            id='drive.pick_title'
            defaultMessage='Attach from drive'
          />
        </NavigationFocusTarget>
      </div>

      <div className='dialog-modal__content'>
        {selecting ? (
          <LoadingIndicator />
        ) : (
          <DriveBrowser
            drive={drive}
            manageable={false}
            onSelectFile={handleSelectFile}
            acceptedTypes={acceptedTypes}
            accept={accept}
          />
        )}
      </div>
    </div>
  );
};
