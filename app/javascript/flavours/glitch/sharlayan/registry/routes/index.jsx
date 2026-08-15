import {
  antennaEnabled,
  circlesEnabled,
  clipsEnabled,
  driveEnabled,
  federationUniverseEnabled,
  pagesEnabled,
  federatedTimelineEnabled,
  localTimelineEnabled,
} from 'flavours/glitch/initial_state';
import { adminTimelineEnabled } from 'flavours/glitch/sharlayan/roleplay';

const alwaysEnabled = () => true;

export const PublicTimeline = () => import('../../../features/public_timeline');
export const CommunityTimeline = () => import('../../../features/community_timeline');
export const ConversationThread = () => import('../../../features/direct_timeline/conversation');
export const AdminTimeline = () => import('../../../features/admin_timeline');
export const AntennaTimeline = () => import('../../../features/antenna_timeline');
export const ReactedStatuses = () => import('../../../features/reacted_statuses');
export const BoardAnnouncements = () => import('../../../features/board_announcements');
export const ClipTimeline = () => import('../../../features/clips/timeline');

export const sharlayanColumnComponents = {
  CONVERSATION: ConversationThread,
  ANTENNA: AntennaTimeline,
  ...(adminTimelineEnabled ? { ADMIN_TIMELINE: AdminTimeline } : {}),
  REACTIONS: ReactedStatuses,
  BOARD_ANNOUNCEMENTS: BoardAnnouncements,
  CLIP: ClipTimeline,
};

export const sharlayanRouteDescriptors = [
  { key: 'public', path: ['/public', '/timelines/public'], exact: true, featureGate: () => federatedTimelineEnabled, lazyComponent: PublicTimeline },
  { key: 'community', path: ['/public/local', '/timelines/public/local'], exact: true, featureGate: () => localTimelineEnabled, lazyComponent: CommunityTimeline },
  { key: 'conversation', path: '/conversations/:conversationId', featureGate: alwaysEnabled, lazyComponent: ConversationThread },
  { key: 'admin-timeline', path: '/timelines/admin', featureGate: () => adminTimelineEnabled, lazyComponent: AdminTimeline },
  { key: 'clip-new', path: '/clips/new', featureGate: () => clipsEnabled, lazyComponent: () => import('../../../features/clips/new') },
  { key: 'clip-favourites', path: '/clips/favourites', exact: true, featureGate: () => clipsEnabled, lazyComponent: () => import('../../../features/clips/favourites') },
  { key: 'clip-edit', path: '/clips/:id/edit', featureGate: () => clipsEnabled, lazyComponent: () => import('../../../features/clips/new') },
  { key: 'clip-show', path: '/clips/:id', featureGate: () => clipsEnabled, lazyComponent: ClipTimeline },
  { key: 'page-new', path: '/pages/new', featureGate: () => pagesEnabled, lazyComponent: () => import('../../../features/pages/editor') },
  { key: 'booklet-new', path: '/pages/booklets/new', featureGate: () => pagesEnabled, lazyComponent: () => import('../../../features/pages/booklet_editor').then(({ BookletEditor }) => ({ default: BookletEditor })) },
  { key: 'booklet-edit', path: '/pages/booklets/:id/edit', featureGate: () => pagesEnabled, lazyComponent: () => import('../../../features/pages/booklet_editor').then(({ BookletEditor }) => ({ default: BookletEditor })) },
  { key: 'page-edit', path: '/pages/:id/edit', featureGate: () => pagesEnabled, lazyComponent: () => import('../../../features/pages/editor') },
  { key: 'page-show', path: '/pages/:id', featureGate: () => pagesEnabled, lazyComponent: () => import('../../../features/pages/show') },
  { key: 'pages', path: '/pages', exact: true, featureGate: () => pagesEnabled, lazyComponent: () => import('../../../features/pages').then(({ Pages }) => ({ default: Pages })) },
  { key: 'circle-new', path: '/circles/new', featureGate: () => circlesEnabled, lazyComponent: () => import('../../../features/circles/new') },
  { key: 'circle-edit', path: '/circles/:id/edit', featureGate: () => circlesEnabled, lazyComponent: () => import('../../../features/circles/new') },
  { key: 'circle-members', path: '/circles/:id/members', featureGate: () => circlesEnabled, lazyComponent: () => import('../../../features/circles/members') },
  { key: 'antenna-edit', path: '/antennas/:id/edit', featureGate: () => antennaEnabled, lazyComponent: () => import('../../../features/antennas/edit') },
  { key: 'antenna-show', path: '/antennas/:id', featureGate: () => antennaEnabled, lazyComponent: AntennaTimeline },
  { key: 'antenna-timeline', path: '/timelines/antenna/:id', featureGate: () => antennaEnabled, lazyComponent: AntennaTimeline },
  { key: 'antennas', path: '/antennas', featureGate: () => antennaEnabled, lazyComponent: () => import('../../../features/antennas') },
  { key: 'reactions', path: '/reactions', featureGate: alwaysEnabled, lazyComponent: ReactedStatuses },
  { key: 'scheduled', path: ['/scheduled', '/timelines/scheduled'], featureGate: alwaysEnabled, lazyComponent: () => import('../../../features/scheduled_timeline') },
  { key: 'drafts', path: '/drafts', exact: true, featureGate: alwaysEnabled, lazyComponent: () => import('../../../features/status_drafts') },
  { key: 'board-announcements', path: '/board_announcements', featureGate: alwaysEnabled, lazyComponent: BoardAnnouncements },
  { key: 'account-clips', path: ['/@:acct/clips', '/accounts/:id/clips'], featureGate: () => clipsEnabled, lazyComponent: () => import('../../../features/account_clips') },
  { key: 'account-page', path: ['/@:acct/pages/:name', '/accounts/:id/pages/:name'], featureGate: () => pagesEnabled, lazyComponent: () => import('../../../features/account_pages/show') },
  { key: 'account-pages', path: ['/@:acct/pages', '/accounts/:id/pages'], exact: true, featureGate: () => pagesEnabled, lazyComponent: () => import('../../../features/account_pages') },
  { key: 'domain-mutes', path: '/domain_mutes', featureGate: alwaysEnabled, lazyComponent: () => import('../../../features/domain_mutes') },
  { key: 'federation-universe', path: '/federation/universe', featureGate: () => federationUniverseEnabled, lazyComponent: () => import('../../../features/federation_universe').then(({ FederationUniverse }) => ({ default: FederationUniverse })) },
  { key: 'custom-emoji-mutes', path: '/custom_emoji_mutes', featureGate: alwaysEnabled, lazyComponent: () => import('../../../features/custom_emoji_mutes') },
  { key: 'reaction-mutes', path: '/reaction_mutes', featureGate: alwaysEnabled, lazyComponent: () => import('../../../features/reaction_mutes') },
  { key: 'clips', path: '/clips', featureGate: () => clipsEnabled, lazyComponent: () => import('../../../features/clips') },
  { key: 'drive', path: '/drive', featureGate: () => driveEnabled, lazyComponent: () => import('../../../features/drive') },
  { key: 'circles', path: '/circles', featureGate: () => circlesEnabled, lazyComponent: () => import('../../../features/circles') },
];
