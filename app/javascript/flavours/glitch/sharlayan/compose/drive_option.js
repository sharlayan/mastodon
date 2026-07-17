import CloudIcon from '@/material-icons/400-24px/cloud.svg?react';

export const addDriveUploadOption = (options, intl, driveEnabled) => {
  if (driveEnabled) {
    options.push({
      icon: 'cloud',
      iconComponent: CloudIcon,
      value: 'drive',
      text: intl.formatMessage({ id: 'compose.attach.drive', defaultMessage: 'Attach from drive' }),
    });
  }

  return options;
};

export const selectDriveUploadOption = (value, onDriveOpen) => {
  if (value !== 'drive') return false;

  onDriveOpen();
  return true;
};
