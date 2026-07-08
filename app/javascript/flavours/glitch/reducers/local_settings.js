//  Package imports.
import { Map as ImmutableMap, List as ImmutableList, fromJS } from 'immutable';

//  Our imports.
import { LOCAL_SETTING_CHANGE, LOCAL_SETTING_DELETE, LOCAL_SETTING_IMPORT } from 'flavours/glitch/actions/local_settings';
import { STORE_HYDRATE } from 'flavours/glitch/actions/store';

const initialState = ImmutableMap({
  fullwidth_columns: false,
  stretch   : true,
  side_arm  : 'none',
  side_arm_reply_mode : 'restrict',
  show_reply_count : true,
  zoom_emojis_on_hover : true,
  always_show_spoilers_field: false,
  confirm_boost_missing_media_description: false,
  confirm_before_clearing_draft: true,
  mention_reblogger: false,
  prepend_cw_re: true,
  preselect_on_reply: true,
  inline_preview_cards: true,
  hicolor_privacy_icons: false,
  show_content_type_choice: false,
  hide_mfm_compose_hint: false,
  show_clip_choice: true,
  show_schedule_button: true,
  tag_misleading_links: true,
  show_follow_list_bio: true,
  inline_compose_timelines: false,
  inline_compose_tabs: ImmutableList(),
  use_publish_toot: false,
  rewrite_mentions: 'no',
  content_warnings : ImmutableMap({
    filter       : null,
    shared_state : false,
  }),
  media     : ImmutableMap({
    letterbox        : true,
    fullwidth        : true,
    reveal_behind_cw : false,
    no_autoplay_gifv : false,
    pop_in_player    : true,
    pop_in_position  : 'right',
  }),
  notifications : ImmutableMap({
    favicon_badge : false,
    tab_badge     : true,
  }),
  status_icons : ImmutableMap({
    language:   true,
    reply:      true,
    local_only: true,
    media:      true,
    visibility: true,
  }),
  navigation_panel : ImmutableMap({
    order  : ImmutableList(),
    hidden : ImmutableMap(),
  }),
  show_published_toast: true,
  sync_to_server: false,
  synced_at: null,
});

const hydrate = (state, localSettings) => state.mergeDeep(localSettings);

export default function localSettings(state = initialState, action) {
  switch(action.type) {
  case STORE_HYDRATE:
    return hydrate(state, action.state.get('local_settings'));
  case LOCAL_SETTING_CHANGE:
    return state.setIn(action.key, action.value);
  case LOCAL_SETTING_DELETE:
    return state.deleteIn(action.key);
  case LOCAL_SETTING_IMPORT:
    return state.mergeDeep(fromJS(action.settings));
  default:
    return state;
  }
}
