# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InitialStateSerializer do
  it 'exposes the server background, mascots, feature gates and reaction limit to guests without signed-in snapshots' do
    background_image = Fabricate(:site_upload, var: 'background_image')
    first = Fabricate(:site_upload, var: 'glitch_mascot1')
    fourth = Fabricate(:site_upload, var: 'glitch_mascot4')
    Setting.background_color = '#102030'
    Setting.background_opacity = 45
    Setting.background_on_settings_pages = true
    serializer = described_class.new(InitialStatePresenter.new(settings: {}))
    meta = serializer.meta

    expect(meta).to include(
      background_color: '#102030',
      background_image: background_image.file.url,
      background_opacity: 45,
      background_on_settings_pages: true,
      glitch_mascots: [first.file.url, nil, nil, fourth.file.url],
      circles_enabled: Setting.circles_enabled,
      clips_enabled: Setting.clips_enabled,
      pages_enabled: Setting.pages_enabled,
      pages_drive_only: Setting.pages_drive_only,
      drive_enabled: Setting.drive_enabled,
      chat_enabled: Setting.chat_enabled,
      roleplay_mode: RoleplayModeHelper.roleplay_mode?,
      user_themes_enabled: Setting.user_themes_enabled,
      user_theme_catalog: Setting.user_theme_catalog,
      user_theme_defaults: Setting.user_theme_defaults
    )
    expect(meta).to_not include(:custom_emoji_mutes, :reaction_mutes)
    expect(serializer.max_reactions).to eq(StatusReactionValidator::LIMIT)
  end

  it 'adds signed-in Sharlayan preferences and mute snapshots with the instance badge seed disabled by default' do
    user = Fabricate(:user)
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})
    meta = described_class.new(presenter).meta

    expect(meta).to include(
      visible_reactions: 6,
      reactions_enabled: Setting.reactions_enabled,
      mfm_fold_mode: 'sensitive',
      ignore_others_pages_view: false,
      avatar_decoration_shape: 'none',
      show_cat: true,
      show_cat_speak: true,
      show_federated_cat: true,
      custom_emoji_mutes: [],
      reaction_mutes: [],
      inline_compose_tabs: [],
      user_theme: '{}',
      server_stored_account_switching_enabled: true,
      show_instance_info: false
    )
  end

  it 'exposes parsed inline compose tabs but not oversized IDs or more than the maximum number of tabs' do
    tabs = {
      valid: [{ type: 'list', id: '123' }],
      oversized: [{ type: 'list', id: '9' * 10_000 }],
      too_many: Array.new(101) { |index| { type: 'list', id: (index + 1).to_s } },
    }
    inline_tabs = tabs.transform_values do |value|
      user = Fabricate(:user)
      user.settings[:inline_compose_tabs] = value.to_json
      described_class.new(InitialStatePresenter.new(current_account: user.account, settings: {})).meta[:inline_compose_tabs]
    end

    expect(inline_tabs).to eq(valid: [{ 'type' => 'list', 'id' => '123' }], oversized: [], too_many: [])
  end

  it 'uses the legacy server instance badge preference as the local default seed' do
    user = Fabricate(:user)
    user.settings.as_json[:'web.show_instance_info'] = true
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

    expect(described_class.new(presenter).meta[:show_instance_info]).to be true
  end

  it 'forces avatar decoration display and MFM rendering in roleplay mode when configured' do
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[]).with('force_avatar_decorations').and_return(true)
      allow(Setting).to receive(:[]).with('force_round_avatar').and_return(true)
      allow(Setting).to receive(:[]).with('force_mfm_enabled').and_return(true)
      user = Fabricate(:user)
      presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

      expect(described_class.new(presenter).meta).to include(
        show_avatar_decorations: true,
        force_round_avatar: true,
        mfm_enabled: true
      )
    end
  end
end
