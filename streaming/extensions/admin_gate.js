/**
 * The management timeline exposes local non-public posts to administrators, so it
 * stays behind its own opt-in flag on top of community (roleplay) mode.
 */
const isAdminTimelineEnabled = () =>
  process.env.OC_ROLEPLAY_OPTION === 'true' &&
  process.env.OC_ADMIN_TIMELINE_OPTION === 'true';

export { isAdminTimelineEnabled };
