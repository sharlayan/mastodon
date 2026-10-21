import type React from 'react';
import { useCallback, useRef } from 'react';

import { FormattedMessage } from 'react-intl';

import classNames from 'classnames';

import {
  ImageSquareIcon,
  ChartBarHorizontalIcon,
  WarningCircleIcon,
  CloudIcon,
  PaintBrushIcon,
  GlobeIcon,
  EyeSlashIcon,
  LockIcon,
  EnvelopeIcon,
} from '@phosphor-icons/react';

import { addPoll, uploadCompose } from '@/flavours/glitch/actions/compose';
import { openModal } from '@/flavours/glitch/actions/modal';
import {
  Button,
  IconButton,
} from '@/flavours/glitch/components/button/redesign';
import {
  Menu,
  MenuItem,
  MenuList,
  MenuTrigger,
} from '@/flavours/glitch/components/menu';
import { driveEnabled } from '@/flavours/glitch/initial_state';
import { submitComposer } from '@/flavours/glitch/reducers/slices/composer';
import {
  createAppSelector,
  useAppDispatch,
  useAppSelector,
} from '@/flavours/glitch/store';

import type { OnEmojiPick } from './emoji';
import { ComposeEmojiButton } from './emoji';
import {
  selectComposeAttachments,
  selectComposeCharsCount,
  selectComposeHasAttachments,
  selectComposeType,
  selectComposeCanSubmit,
  selectComposeSideArm,
} from './selectors';
import classes from './styles.module.scss';

export const ComposeFooter: React.FC<{ onEmojiPick: OnEmojiPick }> = ({
  onEmojiPick,
}) => {
  const type = useAppSelector(selectComposeType);
  const { current, max } = useAppSelector(selectComposeCharsCount);
  const { hasPoll, quotedStatusId } = useAppSelector(
    selectComposeHasAttachments,
  );
  const hasQuote = !!quotedStatusId;
  const isSubmitting = useAppSelector(
    (state) => !!state.compose.get('is_submitting'),
  );
  const isEditing = useAppSelector((state) => !!state.compose.get('id'));
  const scheduledAt = useAppSelector(
    (state) => state.compose.get('scheduled_at') as string | null,
  );
  const usePublishToot = useAppSelector(
    (state) => !!state.local_settings.get('use_publish_toot'),
  );
  const canSubmit = useAppSelector(selectComposeCanSubmit);

  const dispatch = useAppDispatch();
  const handlePoll = useCallback(() => {
    dispatch(addPoll());
  }, [dispatch]);

  let publishText = (
    <FormattedMessage id='compose.publish' defaultMessage='Publish' />
  );
  if (isEditing) {
    publishText = <FormattedMessage id='compose.save' defaultMessage='Save' />;
  } else if (type === 'message' || type === 'replyPrivate') {
    publishText = (
      <FormattedMessage id='compose.message.publish' defaultMessage='Send' />
    );
  } else if (scheduledAt) {
    publishText = (
      <FormattedMessage
        id='compose_form.schedule_submit'
        defaultMessage='Schedule'
      />
    );
  } else if (type === 'reply') {
    publishText = (
      <FormattedMessage id='compose_form.reply' defaultMessage='Reply' />
    );
  } else if (usePublishToot) {
    publishText = (
      <FormattedMessage id='compose_form.publish_toot' defaultMessage='뿌우' />
    );
  }

  return (
    <footer className={classes.footer}>
      <ComposeUploadButton disabled={hasQuote} />

      <ComposeEmojiButton onPick={onEmojiPick} />

      <IconButton
        size='sm'
        icon={ChartBarHorizontalIcon}
        disabled={hasQuote || hasPoll}
        onClick={handlePoll}
      >
        <FormattedMessage
          id='poll_button.add_poll'
          defaultMessage='Add a poll'
        />
      </IconButton>

      <div className={classes.flexGrowWrap}>
        <span
          className={classNames(
            classes.counter,
            current > max && classes.counterError,
          )}
        >
          {current > max && <WarningCircleIcon weight='fill' />}
          <FormattedMessage
            id='compose.counter'
            defaultMessage='{current, number}/{max, number}'
            values={{ current, max }}
          />
        </span>

        <ComposeSideArmButton disabled={!canSubmit} />

        <Button
          variant='solid'
          color='accent'
          type='submit'
          disabled={!canSubmit}
          loading={isSubmitting}
        >
          {publishText}
        </Button>
      </div>
    </footer>
  );
};

const sideArmOptions = {
  public: {
    icon: GlobeIcon,
    label: (
      <FormattedMessage id='privacy.public.short' defaultMessage='Public' />
    ),
  },
  unlisted: {
    icon: EyeSlashIcon,
    label: (
      <FormattedMessage
        id='privacy.unlisted.short'
        defaultMessage='Quiet public'
      />
    ),
  },
  private: {
    icon: LockIcon,
    label: (
      <FormattedMessage id='privacy.private.short' defaultMessage='Followers' />
    ),
  },
  direct: {
    icon: EnvelopeIcon,
    label: (
      <FormattedMessage
        id='privacy.direct.short'
        defaultMessage='Specific people'
      />
    ),
  },
};

export const ComposeSideArmButton: React.FC<{ disabled?: boolean }> = ({
  disabled,
}) => {
  const privacy = useAppSelector(selectComposeSideArm);
  const dispatch = useAppDispatch();
  const onClick = useCallback(() => {
    dispatch(submitComposer({ overridePrivacy: privacy }));
  }, [dispatch, privacy]);

  if (!privacy) return null;

  const { icon, label } = sideArmOptions[privacy];
  return (
    <IconButton icon={icon} disabled={disabled} onClick={onClick}>
      {label}
    </IconButton>
  );
};

const selectUpload = createAppSelector(
  [
    (state) =>
      state.media_attachments.get('accept_content_types') as
        | Immutable.List<string>
        | undefined,
    (state) => !!state.compose.get('is_uploading'),
    selectComposeAttachments,
    (state) => state.compose.get('pending_media_attachments') as number,
    (state) =>
      state.server.server.item?.configuration.statuses.max_media_attachments ??
      4,
    (state) => state.compose.get('resetFileKey') as number,
  ],
  (
    fileTypesList,
    isUploading,
    attachments,
    pendingAttachments,
    maxAttachments,
    resetFileKey,
  ) => {
    const hasVideoOrAudio = attachments.some(
      (attachment) =>
        attachment.type === 'audio' || attachment.type === 'video',
    );
    const hasImages = attachments.some(
      (attachment) => attachment.type === 'image' || attachment.type === 'gifv',
    );
    const fileTypes = (fileTypesList?.toArray() ?? []).filter(
      (fileType) => !hasImages || fileType.startsWith('image/'),
    );
    return {
      accepted: fileTypes.join(','),
      loading: isUploading || pendingAttachments > 0,
      disabled:
        attachments.length + pendingAttachments >= maxAttachments ||
        hasVideoOrAudio,
      resetFileKey,
    };
  },
);

export const ComposeUploadButton: React.FC<{ disabled?: boolean }> = ({
  disabled: disabledProp,
}) => {
  const { accepted, disabled, loading, resetFileKey } =
    useAppSelector(selectUpload);

  const ref = useRef<HTMLInputElement>(null);
  const handleClick = useCallback(() => {
    ref.current?.click();
  }, []);

  const dispatch = useAppDispatch();
  const handleDrive = useCallback(() => {
    dispatch(openModal({ modalType: 'DRIVE', modalProps: {} }));
  }, [dispatch]);
  const handleDoodle = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'DOODLE',
        modalProps: { noEsc: true, noClose: true },
      }),
    );
  }, [dispatch]);
  const handleChange: React.ChangeEventHandler<HTMLInputElement> = useCallback(
    (event) => {
      const files = event.target.files;
      if (files?.length) {
        dispatch(uploadCompose(files));
      }
    },
    [dispatch],
  );

  return (
    <>
      <Menu>
        <MenuTrigger
          as={IconButton}
          size='sm'
          icon={ImageSquareIcon}
          disabled={disabled || disabledProp || loading}
          loading={loading}
        >
          <FormattedMessage
            id='upload_button.label'
            defaultMessage='Add images, a video or an audio file'
          />
        </MenuTrigger>
        <MenuList placement='top-start' maxWidth={280}>
          <MenuItem icon={ImageSquareIcon} onClick={handleClick}>
            <FormattedMessage
              id='upload_button.label'
              defaultMessage='Add images, a video or an audio file'
            />
          </MenuItem>
          <MenuItem icon={PaintBrushIcon} onClick={handleDoodle}>
            <FormattedMessage
              id='compose.attach.doodle'
              defaultMessage='Draw something'
            />
          </MenuItem>
          {driveEnabled && (
            <MenuItem icon={CloudIcon} onClick={handleDrive}>
              <FormattedMessage
                id='compose.attach.drive'
                defaultMessage='Attach from drive'
              />
            </MenuItem>
          )}
        </MenuList>
      </Menu>
      <input
        hidden
        ref={ref}
        type='file'
        multiple
        accept={accepted}
        disabled={disabled || disabledProp || loading}
        key={resetFileKey}
        onChange={handleChange}
      />
    </>
  );
};
