import { sharlayanInitialState } from 'flavours/glitch/initial_state';
import { canViewAdminTimeline } from 'flavours/glitch/permissions';

const {
  adminTimelineOwnerViewer,
  collectionsEnabled,
  forceRoundAvatar,
  roleplayMode,
} = sharlayanInitialState;

export const adminTimelineEnabled = roleplayMode;

export const canUseAdminTimeline = (
  permissions: number,
  extraPermissions: number,
) =>
  adminTimelineEnabled && canViewAdminTimeline(permissions, extraPermissions);

export {
  adminTimelineOwnerViewer,
  collectionsEnabled,
  forceRoundAvatar,
  roleplayMode,
};
