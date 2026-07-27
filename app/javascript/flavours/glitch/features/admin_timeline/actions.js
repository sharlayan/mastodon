import { connectTimelineStream } from '../../actions/streaming';
import { expandTimeline, fillTimelineGaps } from '../../actions/timelines';
import { createAdminStreamConnector } from '../../sharlayan/compose/streaming';

export const adminTimelineId = ({ hidePublic, hideUnlisted, hidePrivate, groupDirect } = {}) => `admin${hidePublic ? ':np' : ''}${hideUnlisted ? ':nu' : ''}${hidePrivate ? ':npv' : ''}${groupDirect ? ':gd' : ''}`;

export const expandAdminTimeline = ({ maxId, hidePublic, hideUnlisted, hidePrivate, groupDirect } = {}) => expandTimeline(adminTimelineId({ hidePublic, hideUnlisted, hidePrivate, groupDirect }), '/api/v1/timelines/admin', { max_id: maxId, hide_public: !!hidePublic, hide_unlisted: !!hideUnlisted, hide_private: !!hidePrivate, group_direct: !!groupDirect });

const fillAdminTimelineGaps = ({ hidePublic, hideUnlisted, hidePrivate, groupDirect } = {}) => fillTimelineGaps(adminTimelineId({ hidePublic, hideUnlisted, hidePrivate, groupDirect }), '/api/v1/timelines/admin', { hide_public: !!hidePublic, hide_unlisted: !!hideUnlisted, hide_private: !!hidePrivate, group_direct: !!groupDirect });

export const connectAdminStream = createAdminStreamConnector({
  adminTimelineId,
  connectTimeline: connectTimelineStream,
  fillGaps: fillAdminTimelineGaps,
});
