import antennas from '../../reducers/antennas';
import { boardAnnouncementsReducer } from '../../reducers/board_announcements';
import { circlesReducer } from '../../reducers/circles';
import { clipsReducer } from '../../reducers/clips';
import { customEmojiMutesReducer } from '../../reducers/custom_emoji_mutes';
import directCompose from '../../reducers/direct_compose';
import favoriteEmojis from '../../reducers/favorite_emojis';
import { reactionMutesReducer } from '../../reducers/reaction_mutes';
import scheduledStatuses from '../../reducers/scheduled_statuses';
import statusDrafts from '../../reducers/status_drafts';
import { accountSwitchesReducer } from '../account_switcher/reducer';

export const sharlayanReducers = {
  accountSwitches: accountSwitchesReducer,
  boardAnnouncements: boardAnnouncementsReducer,
  favorite_emojis: favoriteEmojis,
  clips: clipsReducer,
  circles: circlesReducer,
  antennas,
  custom_emoji_mutes: customEmojiMutesReducer,
  reaction_mutes: reactionMutesReducer,
  direct_compose: directCompose,
  scheduled_statuses: scheduledStatuses,
  status_drafts: statusDrafts,
};
