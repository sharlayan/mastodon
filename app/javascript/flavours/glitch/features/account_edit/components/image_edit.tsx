import { useCallback, useMemo } from 'react';
import type { FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import type { ModalType } from '@/flavours/glitch/actions/modal';
import { openModal } from '@/flavours/glitch/actions/modal';
import type { ApiDriveFileJSON } from '@/flavours/glitch/api_types/drive';
import { Dropdown } from '@/flavours/glitch/components/dropdown_menu';
import { IconButton } from '@/flavours/glitch/components/icon_button';
import { driveEnabled } from '@/flavours/glitch/initial_state';
import type { MenuItem } from '@/flavours/glitch/models/dropdown_menu';
import type { ImageLocation } from '@/flavours/glitch/reducers/slices/profile_edit';
import {
  patchProfile,
  selectImageInfo,
} from '@/flavours/glitch/reducers/slices/profile_edit';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import AddIcon from '@/material-icons/400-24px/add.svg?react';
import CloudIcon from '@/material-icons/400-24px/cloud.svg?react';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import CameraIcon from '@/material-icons/400-24px/photo_camera.svg?react';
import ReplaceImageIcon from '@/material-icons/400-24px/replace_image.svg?react';

import classes from '../styles.module.scss';

const messages = defineMessages({
  add: {
    id: 'account_edit.image_edit.add_button',
    defaultMessage: 'Add image',
  },
  replace: {
    id: 'account_edit.image_edit.replace_button',
    defaultMessage: 'Replace image',
  },
  fromDrive: {
    id: 'account_edit.image_edit.from_drive',
    defaultMessage: 'Use image from Drive',
  },
  driveCopyHint: {
    id: 'account_edit.image_edit.drive_copy_hint',
    defaultMessage:
      'Saves a separate copy that stays if the Drive file is changed or deleted.',
  },
  altAdd: {
    id: 'account_edit.image_edit.alt_add_button',
    description: 'Alt is short for "alternative".',
    defaultMessage: 'Add alt text',
  },
  altEdit: {
    id: 'account_edit.image_edit.alt_edit_button',
    description: 'Alt is short for "alternative".',
    defaultMessage: 'Edit alt text',
  },
  remove: {
    id: 'account_edit.image_edit.remove_button',
    defaultMessage: 'Remove image',
  },
});

export const AccountImageEdit: FC<{
  className?: string;
  location: ImageLocation;
}> = ({ className, location }) => {
  const intl = useIntl();
  const { alt, src } = useAppSelector((state) =>
    selectImageInfo(state, location),
  );
  const descriptionLimit = useAppSelector(
    (state) =>
      state.server.server.item?.configuration.accounts[
        `max_${location}_description_length`
      ] ?? 150,
  );
  const hasAlt = !!alt;
  const dispatch = useAppDispatch();

  const handleModal = useCallback(
    (type: ModalType) => {
      dispatch(openModal({ modalType: type, modalProps: { location } }));
    },
    [dispatch, location],
  );

  const handleDriveSelect = useCallback(
    async (file: ApiDriveFileJSON) => {
      await dispatch(
        patchProfile({
          [`${location}_drive_file_id`]: file.id,
          [`${location}_description`]: Array.from(file.description ?? '')
            .slice(0, descriptionLimit)
            .join(''),
        }),
      ).unwrap();
    },
    [descriptionLimit, dispatch, location],
  );

  const handleDriveClick = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'DRIVE',
        modalProps: {
          acceptedTypes: ['image'],
          accept: 'image/jpeg,image/png,image/gif,image/webp',
          onSelectFile: handleDriveSelect,
        },
      }),
    );
  }, [dispatch, handleDriveSelect]);

  const items = useMemo(() => {
    const menu: MenuItem[] = [
      {
        text: intl.formatMessage(src ? messages.replace : messages.add),
        action: () => {
          handleModal('ACCOUNT_EDIT_IMAGE_UPLOAD');
        },
        icon: src ? ReplaceImageIcon : AddIcon,
      },
    ];

    if (driveEnabled) {
      menu.push({
        text: intl.formatMessage(messages.fromDrive),
        description: intl.formatMessage(messages.driveCopyHint),
        action: handleDriveClick,
        icon: CloudIcon,
      });
    }

    if (src) {
      menu.push(
        {
          text: intl.formatMessage(hasAlt ? messages.altEdit : messages.altAdd),
          action: () => {
            handleModal('ACCOUNT_EDIT_IMAGE_ALT');
          },
          icon: hasAlt ? EditIcon : AddIcon,
        },
        null,
        {
          text: intl.formatMessage(messages.remove),
          action: () => {
            handleModal('ACCOUNT_EDIT_IMAGE_DELETE');
          },
          icon: DeleteIcon,
          dangerous: true,
        },
      );
    }

    return menu;
  }, [handleDriveClick, handleModal, hasAlt, intl, src]);

  const handleAddImage = useCallback(() => {
    handleModal('ACCOUNT_EDIT_IMAGE_UPLOAD');
  }, [handleModal]);

  const iconClassName = classNames(classes.imageButton, className);

  if (!src && !driveEnabled) {
    return (
      <IconButton
        title={intl.formatMessage(messages.add)}
        icon='camera'
        iconComponent={CameraIcon}
        className={iconClassName}
        onClick={handleAddImage}
      />
    );
  }

  return (
    <Dropdown
      items={items}
      placement={location === 'header' ? 'bottom-end' : 'bottom-start'}
      offset={6}
      className={classes.imageMenu}
      icon='camera'
      title={intl.formatMessage(src ? messages.replace : messages.add)}
      iconComponent={CameraIcon}
      iconClassName={iconClassName}
    />
  );
};
