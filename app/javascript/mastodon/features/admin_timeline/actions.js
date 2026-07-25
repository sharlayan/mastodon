import { expandTimeline } from '../../actions/timelines';

export const adminTimelineId = ({ hidePublic, hideUnlisted, hidePrivate, groupDirect } = {}) => `admin${hidePublic ? ':np' : ''}${hideUnlisted ? ':nu' : ''}${hidePrivate ? ':npv' : ''}${groupDirect ? ':gd' : ''}`;

export const expandAdminTimeline = ({ maxId, hidePublic, hideUnlisted, hidePrivate, groupDirect } = {}) => expandTimeline(adminTimelineId({ hidePublic, hideUnlisted, hidePrivate, groupDirect }), '/api/v1/timelines/admin', { max_id: maxId, hide_public: !!hidePublic, hide_unlisted: !!hideUnlisted, hide_private: !!hidePrivate, group_direct: !!groupDirect });
