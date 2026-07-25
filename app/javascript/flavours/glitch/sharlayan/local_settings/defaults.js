import { Map as ImmutableMap, List as ImmutableList, fromJS } from 'immutable';

import { LOCAL_SETTING_IMPORT } from 'flavours/glitch/actions/local_settings';
import { roleplayMode, showInstanceInfo } from 'flavours/glitch/initial_state';
import { STATUS_ACTION_BAR_DEFAULT_HIDDEN } from 'flavours/glitch/features/status_action_bar/items';

export const sharlayanLocalSettingsDefaults = ImmutableMap({
  zoom_emojis_on_hover: true,
  mention_reblogger: false,
  hide_mfm_compose_hint: false,
  hide_compose_language: roleplayMode,
  show_clip_choice: !roleplayMode,
  show_schedule_button: !roleplayMode,
  show_draft_button: false,
  show_follow_list_bio: true,
  show_others_online_status: false,
  show_instance_info: showInstanceInfo === true,
  show_instance_info_local: false,
  inline_compose_timelines: false,
  disable_inline_compose_reply_modal: false,
  inline_compose_tabs: ImmutableList(),
  use_publish_toot: false,
  content_font_size: 'medium',
  sync_to_server: false,
  synced_at: null,
  media: ImmutableMap({
    no_autoplay_gifv: false,
  }),
  navigation_panel: ImmutableMap({
    order: ImmutableList(),
    hidden: ImmutableMap(),
  }),
  status_action_bar: ImmutableMap({
    order: ImmutableList(),
    hidden: ImmutableMap(STATUS_ACTION_BAR_DEFAULT_HIDDEN.map(key => [key, true])),
  }),
});

export function sharlayanLocalSettingsReducer(state, action) {
  switch (action.type) {
  case LOCAL_SETTING_IMPORT:
    return state.mergeDeep(fromJS(action.settings));
  default:
    return state;
  }
}
