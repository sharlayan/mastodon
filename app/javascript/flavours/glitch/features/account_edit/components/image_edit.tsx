import { useCallback, useMemo } from 'react';
import type { FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import {
  ArrowsClockwiseIcon,
  CameraIcon,
  CloudIcon,
  PencilIcon,
  PlusIcon,
  TrashIcon,
} from '@phosphor-icons/react';

import type { ModalType } from '@/flavours/glitch/actions/modal';
import { openModal } from '@/flavours/glitch/actions/modal';
import type { ApiDriveFileJSON } from '@/flavours/glitch/api_types/drive';
import { IconButton } from '@/flavours/glitch/components/button';
import {
  LegacyDropdownMenuItems,
  Menu,
  MenuList,
  MenuTrigger,
} from '@/flavours/glitch/components/menu';
import { driveEnabled } from '@/flavours/glitch/initial_state';
import type { MenuItem } from '@/flavours/glitch/models/dropdown_menu';
import type { ImageLocation } from '@/flavours/glitch/reducers/slices/profile_edit';
import {
  patchProfile,
  selectImageInfo,
} from '@/flavours/glitch/reducers/slices/profile_edit';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

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
        icon: src ? ArrowsClockwiseIcon : PlusIcon,
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
          icon: hasAlt ? PencilIcon : PlusIcon,
        },
        null,
        {
          text: intl.formatMessage(messages.remove),
          action: () => {
            handleModal('ACCOUNT_EDIT_IMAGE_DELETE');
          },
          icon: TrashIcon,
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
        icon={CameraIcon}
        className={iconClassName}
        onClick={handleAddImage}
        size='sm'
        variant='solid'
      >
        {intl.formatMessage(messages.add)}
      </IconButton>
    );
  }

  return (
    <Menu>
      <MenuTrigger
        as={IconButton}
        icon={CameraIcon}
        size='sm'
        variant='solid'
        className={iconClassName}
      >
        {intl.formatMessage(src ? messages.replace : messages.add)}
      </MenuTrigger>
      <MenuList
        offset={6}
        placement={location === 'header' ? 'bottom-end' : 'bottom-start'}
      >
        <LegacyDropdownMenuItems items={items} />
      </MenuList>
    </Menu>
  );
};
