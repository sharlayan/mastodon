'use strict';

const isRoleplayPublicTimelineChannel = (channelName, env = process.env) =>
  env.OC_ROLEPLAY_OPTION === 'true' &&
  (channelName === 'public' || channelName.startsWith('public:'));

export { isRoleplayPublicTimelineChannel };
