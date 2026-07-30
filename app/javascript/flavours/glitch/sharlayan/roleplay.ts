import { sharlayanInitialState } from 'flavours/glitch/initial_state';
import { canViewAdminTimeline } from 'flavours/glitch/permissions';

const {
  adminTimelineEnabled,
  adminTimelineOwnerViewer,
  collectionsEnabled,
  forceRoundAvatar,
  roleplayMode,
  softHideDeletion,
} = sharlayanInitialState;

export const canUseAdminTimeline = (
  permissions: number,
  extraPermissions: number,
) =>
  adminTimelineEnabled && canViewAdminTimeline(permissions, extraPermissions);

export {
  adminTimelineEnabled,
  adminTimelineOwnerViewer,
  collectionsEnabled,
  forceRoundAvatar,
  roleplayMode,
  softHideDeletion,
};
