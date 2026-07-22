# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InitialStateSerializer do
  it 'adds signed-in Sharlayan preferences and mute snapshots' do
    user = Fabricate(:user)
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})
    meta = described_class.new(presenter).meta

    expect(meta).to include(
      visible_reactions: 6,
      reactions_enabled: Setting.reactions_enabled,
      mfm_fold_mode: 'sensitive',
      ignore_others_pages_view: false,
      avatar_decoration_shape: 'none',
      custom_emoji_mutes: [],
      reaction_mutes: []
    )
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

  it 'adds server feature gates for guests without signed-in snapshots' do
    meta = described_class.new(InitialStatePresenter.new(settings: {})).meta

    expect(meta).to include(
      circles_enabled: Setting.circles_enabled,
      clips_enabled: Setting.clips_enabled,
      pages_enabled: Setting.pages_enabled,
      drive_enabled: Setting.drive_enabled,
      roleplay_mode: RoleplayModeHelper.roleplay_mode?
    )
    expect(meta).to_not include(:custom_emoji_mutes, :reaction_mutes)
  end

  it 'exposes the reaction limit as a top-level attribute' do
    serializer = described_class.new(InitialStatePresenter.new(settings: {}))

    expect(serializer.max_reactions).to eq(StatusReactionValidator::LIMIT)
  end
end
