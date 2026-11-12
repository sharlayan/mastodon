import { defineMessages, useIntl } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';

import CloudIcon from '@/material-icons/400-24px/cloud.svg?react';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { NotSignedInIndicator } from 'flavours/glitch/components/not_signed_in_indicator';
import { useIdentity } from 'flavours/glitch/identity_context';

import { DriveBrowser } from './components/drive_browser';
import { DriveSettings } from './components/drive_settings';
import { useDrive } from './use_drive';
import { useDrivePreview } from './use_drive_preview';

const messages = defineMessages({
  heading: { id: 'column.drive', defaultMessage: 'Drive' },
});

const Drive: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { signedIn } = useIdentity();
  const drive = useDrive();
  const handleSelectFile = useDrivePreview(drive.files);

  if (!signedIn) {
    return <NotSignedInIndicator />;
  }

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='cloud'
        iconComponent={CloudIcon}
        title={intl.formatMessage(messages.heading)}
        multiColumn={multiColumn}
        showBackButton
      >
        <DriveSettings folders={drive.folders} onError={drive.onError} />
      </ColumnHeader>

      <div className='scrollable'>
        <DriveBrowser
          drive={drive}
          manageable
          onSelectFile={handleSelectFile}
        />
      </div>

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default Drive;
