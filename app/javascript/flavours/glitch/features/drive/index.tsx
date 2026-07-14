import { useCallback } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { fromJS } from 'immutable';

import { Helmet } from '@unhead/react/helmet';

import CloudIcon from '@/material-icons/400-24px/cloud.svg?react';
import { openModal } from 'flavours/glitch/actions/modal';
import type { ApiDriveFileJSON } from 'flavours/glitch/api_types/drive';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column_header';
import { NotSignedInIndicator } from 'flavours/glitch/components/not_signed_in_indicator';
import { useIdentity } from 'flavours/glitch/identity_context';
import { useAppDispatch } from 'flavours/glitch/store';

import { DriveBrowser } from './components/drive_browser';
import { useDrive } from './use_drive';

const messages = defineMessages({
  heading: { id: 'column.drive', defaultMessage: 'Drive' },
});

const PREVIEWABLE_TYPES = ['image', 'gifv', 'video'];

const Drive: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const { signedIn } = useIdentity();
  const dispatch = useAppDispatch();
  const drive = useDrive();
  const { files } = drive;

  const handleSelectFile = useCallback(
    (file: ApiDriveFileJSON) => {
      if (file.type === 'audio') {
        dispatch(
          openModal({
            modalType: 'AUDIO',
            modalProps: {
              media: fromJS(file),
              options: { autoPlay: true },
            },
          }),
        );

        return;
      }

      if (!PREVIEWABLE_TYPES.includes(file.type)) {
        window.open(file.url, '_blank', 'noopener,noreferrer');

        return;
      }

      const media = files.filter((candidate) =>
        PREVIEWABLE_TYPES.includes(candidate.type),
      );
      const index = media.findIndex((candidate) => candidate.id === file.id);

      dispatch(
        openModal({
          modalType: 'MEDIA',
          modalProps: { media: fromJS(media), index: index < 0 ? 0 : index },
        }),
      );
    },
    [dispatch, files],
  );

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
      />

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
