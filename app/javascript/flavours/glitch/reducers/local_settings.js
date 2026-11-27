//  Package imports.
import { Map as ImmutableMap } from 'immutable';

//  Our imports.
import { LOCAL_SETTING_CHANGE, LOCAL_SETTING_DELETE } from 'flavours/glitch/actions/local_settings';
import { STORE_HYDRATE } from 'flavours/glitch/actions/store';
import { sharlayanLocalSettingsDefaults, sharlayanLocalSettingsReducer } from 'flavours/glitch/sharlayan/local_settings/defaults';
import { useMyArchive } from 'flavours/glitch/initial_state';

const initialState = ImmutableMap({
  confirm_boost_missing_media_description: false,
  confirm_before_clearing_draft: true,
  prepend_cw_re: true,
  preselect_on_reply: true,
  inline_preview_cards: true,
  tag_misleading_links: true,
  rewrite_mentions: 'no',
  media     : ImmutableMap({
    letterbox        : true,
    fullwidth        : true,
    reveal_behind_cw : false,
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
  show_published_toast: true,
}).mergeDeep(sharlayanLocalSettingsDefaults);

const hydrate = (state, localSettings) => state.mergeDeep(localSettings).set('use_my_archive', useMyArchive);

/** @type {import('@reduxjs/toolkit').Reducer<ImmutableMap<string, unknown>>} */
export default function localSettings(state = initialState, action) {
  switch(action.type) {
  case STORE_HYDRATE:
    return hydrate(state, action.state.get('local_settings'));
  case LOCAL_SETTING_CHANGE:
    return state.setIn(action.key, action.value);
  case LOCAL_SETTING_DELETE:
    return state.deleteIn(action.key);
  default:
    return sharlayanLocalSettingsReducer(state, action);
  }
}
