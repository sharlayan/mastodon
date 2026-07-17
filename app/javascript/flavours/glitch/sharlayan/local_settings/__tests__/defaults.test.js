import { Map as ImmutableMap, List as ImmutableList } from 'immutable';

import localSettings from 'flavours/glitch/reducers/local_settings';

import { sharlayanLocalSettingsDefaults } from '../defaults';

const initial = () => localSettings(undefined, { type: '@@INIT' });

describe('sharlayan local_settings defaults', () => {
  it('merges every Sharlayan default into the reducer initial state', () => {
    const state = initial();

    expect(state.get('show_follow_list_bio')).toBe(true);
    expect(state.get('show_others_online_status')).toBe(false);
    expect(state.get('inline_compose_timelines')).toBe(false);
    expect(state.get('use_publish_toot')).toBe(false);
    expect(state.get('hide_compose_language')).toBe(false);
    expect(state.get('hide_mfm_compose_hint')).toBe(false);
    expect(state.get('show_clip_choice')).toBe(true);
    expect(state.get('show_schedule_button')).toBe(true);
    expect(state.get('mention_reblogger')).toBe(false);
    expect(state.get('zoom_emojis_on_hover')).toBe(true);
    expect(state.get('sync_to_server')).toBe(false);
    expect(state.get('synced_at')).toBe(null);
    expect(state.get('inline_compose_tabs')).toEqual(ImmutableList());
  });

  it('deep-merges nested defaults without dropping upstream keys', () => {
    const state = initial();

    expect(state.getIn(['media', 'no_autoplay_gifv'])).toBe(false);
    expect(state.getIn(['media', 'letterbox'])).toBe(true);
    expect(state.getIn(['media', 'pop_in_position'])).toBe('right');
    expect(state.get('navigation_panel')).toEqual(
      ImmutableMap({ order: ImmutableList(), hidden: ImmutableMap() }),
    );
  });

  it('preserves upstream defaults untouched', () => {
    const state = initial();

    expect(state.get('stretch')).toBe(true);
    expect(state.get('hicolor_privacy_icons')).toBe(false);
    expect(state.getIn(['status_icons', 'visibility'])).toBe(true);
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

  it('exposes the defaults map for registry consumers', () => {
    expect(sharlayanLocalSettingsDefaults.get('sync_to_server')).toBe(false);
  });
});
