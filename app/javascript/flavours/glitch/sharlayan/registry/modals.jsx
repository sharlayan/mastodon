import { ConfirmDeleteCircleModal } from 'flavours/glitch/features/ui/components/confirmation_modals';
import { ConversationParticipantsModal } from 'flavours/glitch/features/ui/components/conversation_participants_modal';
import { MfmPreviewModal } from 'flavours/glitch/features/ui/components/mfm_preview_modal';

const accountEditModal = (type) => () =>
  import('@/flavours/glitch/features/account_edit/modals').then((module) => ({
    default: module[type],
  }));

export const sharlayanModalComponents = {
  CONFIRM_DELETE_CIRCLE: () =>
    Promise.resolve({ default: ConfirmDeleteCircleModal }),
  DOMAIN_MUTE: () =>
    import('flavours/glitch/features/ui/components/domain_mute_modal'),
  REPORT_PAGE: () =>
    import('flavours/glitch/features/ui/components/report_page_modal').then(
      (module) => ({ default: module.ReportPageModal }),
    ),
  CLIP_ADD: () =>
    import('@/flavours/glitch/features/clip_adder').then((module) => ({
      default: module.ClipAdder,
    })),
  DRIVE: () =>
    import('@/flavours/glitch/features/drive_modal').then((module) => ({
      default: module.DriveModal,
    })),
  DRIVE_FOLDER_NAME: () =>
    import('@/flavours/glitch/features/drive/components/name_modal').then(
      (module) => ({ default: module.DriveFolderNameModal }),
    ),
  DRIVE_FILE_NAME: () =>
    import('@/flavours/glitch/features/drive/components/name_modal').then(
      (module) => ({ default: module.DriveFileNameModal }),
    ),
  MFM_PREVIEW: () => Promise.resolve({ default: MfmPreviewModal }),
  CONVERSATION_PARTICIPANTS: () =>
    Promise.resolve({ default: ConversationParticipantsModal }),
  ACCOUNT_SWITCHER: () =>
    import('@/flavours/glitch/features/account_switcher').then((module) => ({
      default: module.AccountSwitcherModal,
    })),
  ACCOUNT_EDIT_DECORATION: accountEditModal('DecorationModal'),
  ACCOUNT_EDIT_FOLLOW_MESSAGE: accountEditModal('FollowMessageModal'),
};
