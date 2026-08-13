# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InitialStateSerializer do
  it 'adds signed-in Sharlayan preferences and mute snapshots' do
    user = Fabricate(:user)
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})
    meta = described_class.new(presenter).meta

    expect(meta).to include(
      visible_reactions: 6,
      federation_universe_enabled: Sharlayan::FederationEdgeAggregator.enabled?,
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
      user_theme: '{}'
    )
  end

  it 'exposes parsed inline compose tabs for the signed-in user' do
    user = Fabricate(:user)
    user.settings[:inline_compose_tabs] = [{ type: 'list', id: '123' }].to_json
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

    expect(described_class.new(presenter).meta[:inline_compose_tabs]).to eq([{ 'type' => 'list', 'id' => '123' }])
  end

  it 'does not expose oversized inline compose tab IDs' do
    user = Fabricate(:user)
    user.settings[:inline_compose_tabs] = [{ type: 'list', id: '9' * 10_000 }].to_json
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

    expect(described_class.new(presenter).meta[:inline_compose_tabs]).to eq([])
  end

  it 'does not expose more than the maximum number of inline compose tabs' do
    user = Fabricate(:user)
    user.settings[:inline_compose_tabs] = Array.new(101) { |index| { type: 'list', id: (index + 1).to_s } }.to_json
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

    expect(described_class.new(presenter).meta[:inline_compose_tabs]).to eq([])
  end

  it 'uses the legacy server instance badge preference as the local default seed' do
    user = Fabricate(:user)
    user.settings.as_json[:'web.show_instance_info'] = true
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

    expect(described_class.new(presenter).meta[:show_instance_info]).to be true
  end

  it 'defaults the local instance badge seed to disabled without a legacy preference' do
    user = Fabricate(:user)
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

    expect(described_class.new(presenter).meta[:show_instance_info]).to be false
  end

  it 'forces avatar decoration display in roleplay mode when configured' do
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[])
        .with('force_avatar_decorations')
        .and_return(true)
      allow(Setting).to receive(:[])
        .with('force_round_avatar')
        .and_return(true)
      user = Fabricate(:user)
      presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

      expect(described_class.new(presenter).meta).to include(
        show_avatar_decorations: true,
        force_round_avatar: true
      )
    end
  end

  it 'forces MFM rendering in roleplay mode when configured' do
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[]).with('force_mfm_enabled').and_return(true)
      user = Fabricate(:user)
      presenter = InitialStatePresenter.new(current_account: user.account, settings: {})

      expect(described_class.new(presenter).meta[:mfm_enabled]).to be(true)
    end
  end

  it 'adds server feature gates for guests without signed-in snapshots' do
    meta = described_class.new(InitialStatePresenter.new(settings: {})).meta

    expect(meta).to include(
      circles_enabled: Setting.circles_enabled,
      clips_enabled: Setting.clips_enabled,
      pages_enabled: Setting.pages_enabled,
      pages_drive_only: Setting.pages_drive_only,
      drive_enabled: Setting.drive_enabled,
      roleplay_mode: RoleplayModeHelper.roleplay_mode?,
      user_themes_enabled: Setting.user_themes_enabled,
      user_theme_catalog: Setting.user_theme_catalog,
      user_theme_defaults: Setting.user_theme_defaults
    )
    expect(meta).to_not include(:custom_emoji_mutes, :reaction_mutes, :federation_universe_enabled)
  end

  it 'exposes the reaction limit as a top-level attribute' do
    serializer = described_class.new(InitialStatePresenter.new(settings: {}))

    expect(serializer.max_reactions).to eq(StatusReactionValidator::LIMIT)
  end
end
