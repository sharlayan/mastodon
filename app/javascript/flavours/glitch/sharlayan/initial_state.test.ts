import { readSharlayanInitialState } from './initial_state';
import type { SharlayanInitialStateMeta } from './initial_state';

const meta: SharlayanInitialStateMeta = {
  max_reactions: 3,
  force_local_only: true,
  circles_enabled: true,
  clips_enabled: true,
  pages_enabled: true,
  antenna_enabled: true,
  drive_enabled: true,
  board_announcements_enabled: true,
  avatar_decorations_enabled: true,
  avatar_decorations_federation_enabled: true,
  color_scheme: 'dark',
  contrast: 'high',
  show_avatar_decorations: true,
  show_federated_avatar_decorations: true,
  avatar_decoration_shape: 'square',
  local_account_statuses_access: 'authenticated',
  local_status_page_access: 'public',
  roleplay_mode: false,
  visible_reactions: 8,
  show_instance_info: true,
  custom_emoji_size: true,
  reaction_custom_emoji_size: true,
  reaction_local_emoji_only: true,
  reactions_enabled: true,
  mfm_enabled: true,
  mfm_animations: true,
  mfm_fold_mode: 'all',
  mfm_allow_composition: true,
};

describe('Sharlayan initial state', () => {
  it('preserves enabled metadata and its exported defaults', () => {
    expect(readSharlayanInitialState({ meta, max_reactions: 5 })).toMatchObject(
      {
        maxReactions: 5,
        driveEnabled: true,
        antennaEnabled: true,
        showInstanceInfo: true,
        mfmFoldMode: 'all',
        avatarDecorationShape: 'square',
        customEmojiMutes: [],
        reactionMutes: [],
      },
    );
  });

  it('keeps gate-off and guest defaults when state is absent', () => {
    expect(readSharlayanInitialState()).toMatchObject({
      maxReactions: 1,
      driveEnabled: false,
      antennaEnabled: false,
      reactionsEnabled: true,
      mfmEnabled: true,
      mfmFoldMode: 'sensitive',
      avatarDecorationShape: 'round',
    });
  });
});
