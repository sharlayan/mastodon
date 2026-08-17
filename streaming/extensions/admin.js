import { AuthenticationError } from '../errors.js';
import { isAdminTimelineEnabled } from './admin_gate.js';

const CHANNEL_NAME = 'admin';
const EXTRA_PERMISSION_VIEW_ADMIN_TIMELINE = 1 << 1;
const EXTRA_PERMISSION_VIEW_FOLLOWERS_ADMIN_TIMELINE = 1 << 2;

const enabled = isAdminTimelineEnabled;

const channelNameFromPath = (path) => enabled() && path === '/api/v1/streaming/admin' ? CHANNEL_NAME : undefined;

const authorizeChannel = (req, name) => {
  if (name !== CHANNEL_NAME) return undefined;
  if (!enabled()) {
    throw new AuthenticationError('Management timeline is disabled');
  }
  if (!(req.extraPermissions & (EXTRA_PERMISSION_VIEW_ADMIN_TIMELINE | EXTRA_PERMISSION_VIEW_FOLLOWERS_ADMIN_TIMELINE))) {
    throw new AuthenticationError('Not authorized to stream the management timeline');
  }

  return {
    channelIds: [req.adminTimelineOwnerViewer ? 'timeline:admin:owner' : req.extraPermissions & EXTRA_PERMISSION_VIEW_ADMIN_TIMELINE ? 'timeline:admin' : `timeline:admin:followers:${req.accountId}`],
    options: { needsFiltering: false, allowLocalOnly: true },
  };
};

export { CHANNEL_NAME, authorizeChannel, channelNameFromPath };
