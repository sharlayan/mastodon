import { Map as ImmutableMap, List as ImmutableList, fromJS } from 'immutable';

import localSettings from 'flavours/glitch/reducers/local_settings';
import { showInstanceInfo } from 'flavours/glitch/initial_state';
import { roleplayMode } from 'flavours/glitch/sharlayan/roleplay';

import { sharlayanLocalSettingsDefaults } from '../defaults';

const initial = () => localSettings(undefined, { type: '@@INIT' });

describe('sharlayan local_settings defaults', () => {
  it('merges every Sharlayan default into the reducer initial state', () => {
    const state = initial();

    expect(state.get('show_follow_list_bio')).toBe(true);
    expect(state.get('show_others_online_status')).toBe(false);
    expect(state.get('show_instance_info')).toBe(showInstanceInfo === true);
    expect(state.get('inline_compose_timelines')).toBe(roleplayMode);
    expect(state.get('inline_compose_expand_on_click')).toBe(false);
    expect(state.get('disable_inline_compose_reply_modal')).toBe(false);
    expect(state.get('use_publish_toot')).toBe(false);
    expect(state.get('deck_unpinned_column_width')).toBe(350);
    expect(state.get('content_font_size')).toBe('medium');
    expect(state.get('sensitive_emoji_display')).toBe('show');
    expect(state.get('hide_compose_language')).toBe(false);
    expect(state.get('hide_mfm_compose_hint')).toBe(false);
    expect(state.get('show_clip_choice')).toBe(true);
    expect(state.get('show_schedule_button')).toBe(true);
    expect(state.get('mention_reblogger')).toBe(false);
    expect(state.get('zoom_emojis_on_hover')).toBe(true);
    expect(state.get('sync_to_server')).toBe(false);
    expect(state.get('synced_at')).toBe(null);
    expect(state.getIn(['collapsed', 'enabled'])).toBe(false);
    expect(state.getIn(['collapsed', 'auto', 'notifications'])).toBe(true);
    expect(state.getIn(['collapsed', 'auto', 'lengthy'])).toBe(true);
    expect(state.getIn(['collapsed', 'auto', 'character_limit'])).toBe('');
    expect(state.getIn(['collapsed', 'auto', 'height'])).toBe(400);
    expect(state.getIn(['collapsed', 'show_action_bar'])).toBe(true);
  });

  it('deep-merges nested defaults without dropping upstream keys', () => {
    const state = initial();

    expect(state.getIn(['media', 'no_autoplay_gifv'])).toBe(false);
    expect(state.getIn(['media', 'letterbox'])).toBe(true);
    expect(state.getIn(['media', 'pop_in_position'])).toBe('right');
    expect(state.get('navigation_panel')).toEqual(
      ImmutableMap({ order: ImmutableList(), hidden: ImmutableMap() }),
    );
    expect(state.get('status_action_bar')).toEqual(
      ImmutableMap({
        order: ImmutableList(),
        hidden: ImmutableMap({ clip: true, quote: true }),
      }),
    );
  });

  it('preserves upstream defaults untouched', () => {
    const state = initial();

    expect(state.get('stretch')).toBe(true);
    expect(state.get('hicolor_privacy_icons')).toBe(false);
    expect(state.getIn(['status_icons', 'visibility'])).toBe(true);
  });

  it('stores the shared width for the unpinned deck column', () => {
    const state = localSettings(initial(), {
      type: 'LOCAL_SETTING_CHANGE',
      key: ['deck_unpinned_column_width'],
      value: 520,
    });

    expect(state.get('deck_unpinned_column_width')).toBe(520);
  });

  it('applies LOCAL_SETTING_IMPORT via the Sharlayan reducer branch', () => {
    const state = localSettings(initial(), {
      type: 'LOCAL_SETTING_IMPORT',
      settings: { use_publish_toot: true, media: { no_autoplay_gifv: true } },
    });

    expect(state.get('use_publish_toot')).toBe(true);
    expect(state.getIn(['media', 'no_autoplay_gifv'])).toBe(true);
    expect(state.getIn(['media', 'letterbox'])).toBe(true);
  });

  it('prefers a stored local instance badge setting over the server seed', () => {
    const storedValue = showInstanceInfo !== true;
    const state = localSettings(initial(), {
      type: 'STORE_HYDRATE',
      state: fromJS({ local_settings: { show_instance_info: storedValue } }),
    });

    expect(state.get('show_instance_info')).toBe(storedValue);
  });

  it('exposes the defaults map for registry consumers', () => {
    expect(sharlayanLocalSettingsDefaults.get('sync_to_server')).toBe(false);
  });
});
